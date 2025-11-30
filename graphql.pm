#!/usr/bin/env perl
package graphql;
use strict;
use warnings;

use feature qw/ say state /;

use base 'Exporter';
our @EXPORT = qw/
	graphql_query
/;

use Data::Dumper;


sub parse_graphql_query {
	my ($query) = @_;
	my @tokens = tokenize_graphql($query);
	return parse_tokens(\@tokens);
}

# Tokenizer: breaks the query into tokens
sub tokenize_graphql {
	my ($query) = @_;
	$query =~ s/^\s+|\s+$//g;    # Trim leading and trailing whitespace
	my @tokens;
	while ($query =~ /
		([{}])|                   # Match braces
		([()])|                   # Match paren
		([a-z_][a-z0-9_]*)|       # Match field names
		("[^"\\]*")|              # Match strings
        ('[^'\\]*')|              # Match single-quote strings
		([-+]?\d+)|               # Match numbers
		([,])|                    # Match commas
		(:)|                      # Match colons
		(\s+)                     # Match whitespace
	/xig) {
		push @tokens, $1 // $2 // $3 // $4 // $5 // $6 // $7 // $8 if defined ($1 // $2 // $3 // $4 // $5 // $6 // $7 // $8);
	}
	return @tokens;
}

# Recursive parser for GraphQL tokens
sub parse_tokens {
	my ($tokens, $result) = @_;
	$result //= {};

	die "expected '{' at block start, instead got $tokens->[0]" if $tokens->[0] ne '{';
	shift @$tokens;
	while (@$tokens) {
		my $token = shift @$tokens;
		# say "token: $token";
		if ($token eq '}') {
			last; # End of this level
		} elsif ($token =~ /^[a-zA-Z_]/) { # Field name
			my $name = $token;
			my $value = $token;
			if ($tokens->[0] eq ':') { # Argument key
				shift @$tokens; # Consume ':'
				$value = shift @$tokens; # Argument value
				# say "got $name -> $value";
			}

			$result->{$name} = { _key => $value };

			if ($tokens->[0] eq '(') {
                shift @$tokens; # Consume '('
                $result->{$name}{_params} = parse_params($tokens);
                die "expected ')' after parameters" unless shift @$tokens eq ')'; # Consume ')'
            }

			if ($tokens->[0] eq '{') { # Nested object
				$result->{$name}{_nested} = parse_tokens($tokens);
			}
		} else {
			die "unexpected token: $token";
		}
	}
	return $result;
}

# Helper function to parse parameters (e.g., x:-1, y:1)
sub parse_params {
    my ($tokens) = @_;
    my %params;

    while ($tokens->[0] ne ')') {
        my $key = shift @$tokens;
        die "expected argument key, got: $key" unless $key =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/;

        die "expected ':' after argument key" unless shift @$tokens eq ':';

        my $value = shift @$tokens;
        die "expected argument value, got: $value" unless $value =~ /^([-+]?\d+(\.\d+)?|[a-zA-Z_][a-zA-Z0-9_]*|"[^"\\]*"|'[^'\\]*')$/;
        $value = $1 // $2 if $value =~ /^"([^"\\]*)"|'([^'\\]*)'$/;

        $params{$key} = $value;

        shift @$tokens if $tokens->[0] eq ',';
    }

    return \%params;
}

my @pos_table = 'a' .. 'z';

sub execute_graphql_code {
	my ($code, $context) = @_;
	my %result;
	return undef unless defined $context;

	# say Dumper $context;
	# say "exec: ", Dumper $code;
	foreach my $name (keys %$code) {
		my $key = $code->{$name}{_key};
		# say "wat: $name -> $code->{$name}";
		if (exists $context->{$key}) {
			my $val = $context->{$key};

			if (exists $code->{$name}{_params} or 'CODE' eq ref $val) {
				$val = $val->($context, $code->{$name}{_params});
				# say "got modified val:", Dumper $val;
			}
			if (exists $code->{$name}{_nested}) {
				# say "recurse:", Dumper $val;
				$val = execute_graphql_code($code->{$name}{_nested}, $val);
			}
			$result{$name} = $val;
		} else {
			die "Unsupported query key: $key, context is: " . Dumper $context;
		}
	}

	return \%result;
}

sub get_value {
	my ($arr, $coord) = @_;
	my $value = $arr;
	my () = map { $value = $_ < 0 ? undef : $value->[$_] } @$coord;
    return $value;
}

our %graphql_methods = (
    neighbor => sub {
        my ($self, $params) = @_;
        my $new_coord = [ map { $params->{"abs_$pos_table[$_]"} // ($self->{coord}[$_] + ($params->{"d$pos_table[$_]"} // 0)) } 0 .. $#{$self->{coord}} ];
        return get_context($self->{arr}, $new_coord);
    },
    delta => sub {
        my ($self, $params) = @_;
        my $new_coord = [ map { $params->{"abs_$pos_table[$_]"} // ($self->{coord}[$_] + ($params->{"d$pos_table[$_]"} // 0)) } 0 .. $#{$self->{coord}} ];
        my $ctx = get_context($self->{arr}, $new_coord);
        if (defined $ctx) {
            $ctx->{value} = ($self->{value} // 0) - ($ctx->{value} // 0);
        }
        return $ctx;
    },
);

$graphql::graphql_methods{where} = sub {
        my ($self, $params) = @_;
        return (defined ($self->{value}) and $self->{value} eq $params->{value}) ? $self : undef;
    };
$graphql::graphql_methods{row} = sub {
        my ($self, $params) = @_;
        my @row = @{$self->{arr}[$self->{coord}[0]]};
        return [ @row ];
    };
sub cached_single_arg {
    my ($fun) = @_;
    return sub {
        my ($arg) = @_;
        state %cached_single_arg_table;
        unless (exists $cached_single_arg_table{$fun}{$arg}) {
            $cached_single_arg_table{$fun}{$arg} = $fun->($arg);
        }
        return $cached_single_arg_table{$fun}{$arg};
    }
}
*selector = cached_single_arg(sub { eval 'sub { $_ ? $_->' . join ('', map "{$_}", split /\./, $_[0]) . ' : undef }' });

sub subp { my ($a, $b) = @_; return [ map { $a->[$_] - $b->[$_] } 0 .. $#$a ]; }
sub addp { my ($a, $b) = @_; return [ map { $a->[$_] + $b->[$_] } 0 .. $#$a ]; }
sub stringp { my ($p) = $_[0] // $_; return join ',', @$p }
sub uniqp { my %h; @h{map $_->[0].','.$_->[1], @_} = (); map [ split ',' ], keys %h }
sub in_bounds {
    my ($p, @shape) = @_;
    return $p->[0] >= 0 && $p->[1] >= 0 && $p->[0] < $shape[0] && $p->[1] < $shape[1];
}
sub adjacent_points {
    my ($p, @shape) = @_;
    my @adj;
    return grep in_bounds($_, @shape), map addp($p, $_), [-1,0],[1,0],[0,-1],[0,1];
}
$graphql::graphql_methods{flood_group} = sub {
        my ($self, $params) = @_;
        my $arr = $self->{arr};
        my @shape = shape($self->{arr});

        state %flood_group_cache;

        return $flood_group_cache{$arr}{stringp($self->{coord})} if exists $flood_group_cache{$arr}{stringp($self->{coord})};
        
        my $key = $self->{value};
        my %group;
        my @next_points = ($self->{coord});
        my $rep = 0;
        while (@next_points) {
            die if $rep++ > 50;
            @group{map stringp, @next_points} = ();
            @next_points =
                uniqp
                grep { not exists $group{stringp $_} }
                grep $arr->[$_->[0]][$_->[1]] eq $key,
                map adjacent_points($_, @shape),
                @next_points;
        }
        my $ret = [ map [split ','], keys %group ];
        foreach (@$ret) {
            $flood_group_cache{$arr}{stringp $_} = $ret;
        }
        return $ret;
    };
$graphql::graphql_methods{group_by} = sub {
        my ($self, $params) = @_;
        my $key = $params->{key};
        my $arr = $self->{arr};

        state $cached //= {};

        $cached->{"$arr/$key"} = {
            group_by selector($key),
            flatten_nd
            $self->{arr}
        } unless exists $cached->{"$arr/$key"};
        return $cached->{"$arr/$key"};
    };

sub get_context {
	my ($arr, $coord) = @_;

	for (@$coord) {
		if ($_ < 0) {
			return undef;
		}
	}

	my $value = get_value($arr, $coord);
	my $pos = { map { $pos_table[$_] => $coord->[$_] } 0 .. $#$coord };
	my $context = {
        arr => $arr,
		value => $value,
		pos => $pos,
        coord => $coord,
        %graphql_methods,
	};

	return $context;
}

sub _graphql_query {
	my ($query) = @_;
	my $code = parse_graphql_query($query);
	# say Dumper $code;
	my $handler;
	$handler = sub {
		my $context = get_context(@_);
		return execute_graphql_code($code, $context);
	};
}
*graphql_query = cached_single_arg(sub { _graphql_query(@_) });

1;
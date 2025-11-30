use strict;
use warnings;

use feature qw/ say state /;
use Data::Dumper;

sub readfile { local $/; my $file = IO::File->new($_[0], 'r'); <$file> }
sub writefile { local $/; my $file = IO::File->new($_[0], 'w'); $file->print($_[1]) }
sub appendfile { local $/; my $file = IO::File->new($_[0], 'a'); $file->print($_[1]) }

sub sum { my $s = 0; foreach my $n (@_) { $s += $n } $s }
sub product { my $p = 1; foreach my $n (@_) { $p *= $n } $p }
sub min { (sort { $a <=> $b } @_)[0] }
sub max { (sort { $a <=> $b } @_)[-1] }
sub reduce (&$@) { my ($fun, $reduced, @values) = @_; for (@values) { $reduced = $fun->($reduced, $_) } $reduced }
sub freq { my %freq; $freq{$_}++ for @_; return %freq; }
sub uniq { my %h; @h{@_} = (); keys %h }
sub all (&@) { my ($fun, @args) = @_; foreach (@args) { return 0 unless $fun->() } return 1 }
sub none (&@) { my ($fun, @args) = @_; foreach (@args) { return 0 if $fun->() } return 1 }
sub first (&@) { my ($fun, @args) = @_; foreach (@args) { return $_ if $fun->() } return undef }
sub shuffle { map $_->[1], sort { $a->[0] <=> $b->[0] } map [rand, $_], @_ }

sub round { sprintf "%.0f", $_[0] }

# n-dimensional mapper function
sub map_nd {
	my ($fun, $arr) = @_;
	return [ map { $fun->($_) } @$arr ] if (@$arr >= 0 and ref $arr->[0] ne 'ARRAY');
	return [ map map_nd($fun, $_), @$arr ];
}
sub slice_nd {
    my ($slices, $arr) = @_;
    my $current_slice = $slices->[0];
    my @next_slices = @$slices[1 .. $#$slices];
    my $start = $current_slice->[0] // 0;
    my $end = $current_slice->[1] // $#$arr;
    $start += @$arr if $start < 0;
    $end += @$arr if $end < 0;
    
    return [ map { slice_nd(\@next_slices, $_) } @$arr[$start .. $end] ] if @next_slices;
    return [ @$arr[$start .. $end] ];
}
# Function to determine the dimensionality and lengths in each dimension of an n-dimensional array
sub shape {
	my ($arr) = @_;
	my @dims;
	while (ref $arr eq 'ARRAY') {
		push @dims, scalar @$arr;
		$arr = $arr->[0];
	}
	return @dims;
}
# n-dimensional flatten function
sub flatten_nd {
	my ($arr) = @_;
	return @$arr if (@$arr >= 0 and ref $arr->[0] ne 'ARRAY');
	return map flatten_nd($_), @$arr;
}

sub get_value {
	my ($arr, $coord) = @_;
	my $value = $arr;
	my () = map { $value = $_ < 0 ? undef : $value->[$_] } @$coord;
    return $value;
}

# n-dimensional mapper function with coordinates
sub map_nd_indexed {
	my ($fun, $arr, $iter, @coords) = @_;
	$iter //= $arr;
	return [ map $fun->($arr, [ @coords, $_ ], get_value($arr, [ @coords, $_ ])), 0 .. $#$iter ] if (@$iter >= 0 and ref $iter->[0] ne 'ARRAY');
	return [ map map_nd_indexed($fun, $arr, $iter->[$_], @coords, $_), 0 .. $#$iter ];
}
sub map_rows {
    my ($fun, $arr) = @_;
	return [ map { $fun->($_) } @$arr ] if (@$arr >= 0 and ref $arr->[0][0] ne 'ARRAY');
	return [ map map_rows($fun, $_), @$arr ];
}

sub nd_from_shape {
    my @shape = @_;
    return [ map undef, 0 .. $shape[0] - 1 ] if @shape == 1;
    return [ map nd_from_shape(@shape[1 .. $#shape]), 0 .. $shape[0] - 1 ];
}
sub parse_2d_string_array {
    my ($input) = @_;
    return [ map [ split ], grep $_, split /\n/, $input ];
}
sub parse_2d_map_array {
    my ($input) = @_;
    return [ map [ split '' ], grep $_, split /\n/, $input ];
}
sub string_2d_map_array {
    my ($arr) = @_;
    return join "\n", map { join '', @$_ } @$arr;
}
sub string_2d_numbers_array {
    my ($arr) = @_;
    return join "\n", map { join '', map { defined ? sprintf "% 6d|", $_ : '      |' } @$_ } @$arr;
}

sub transpose_2d (@) {
    my ($arr) = @_;
    return [ map { my $i = $_; [ map $_->[$i], @$arr ] } 0 .. $#{$arr->[0]} ]
}

sub group {
    my (@data) = @_;
    my %table;
    foreach (@data) {
        push @{$table{$_}}, $_;
    }
    return %table;
}

sub group_by {
    my ($fun, @args) = @_;
    my %table;
    if (ref $fun eq 'CODE') {
        foreach (@args) {
            push @{$table{$fun->($_)}}, $_;
        }
    } else {
        foreach (@args) {
            push @{$table{$_->{$_}}}, $_;
        }
    }
    return %table;
}
sub map_groups {
    my ($fun, %groups) = @_;
    my %res = map $fun->($_, $groups{$_}), keys %groups;
    return %res;
}

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

our $timer_start_timestamp;
sub timecheck { die "time out!" if defined $timer_start_timestamp and time - $timer_start_timestamp >= ($_[0] // 15); }
sub timer { $timer_start_timestamp = time; $_[0]->(); my $time = time - $timer_start_timestamp; say "[time] $time seconds"; $timer_start_timestamp = undef; $time }
sub confirm { my ($a, $b) = @_; die "expiremental '$a' doesn't match expected $b" unless $a eq $b; say "confirmed: $a"; return $a }

our $cache_miss = 0;
our $cache_hit = 0;

sub cached_args {
    my ($fun) = @_;
    return sub {
        my $key = join ',', @_;
        state %cached_single_arg_table;
        unless (exists $cached_single_arg_table{$fun}{$key}) {
            $cache_miss++;
            # say "no hit: $key";
            $cached_single_arg_table{$fun}{$key} = [ $fun->(@_) ];
        } else {
            $cache_hit++;
        }
        return @{$cached_single_arg_table{$fun}{$key}};
    }
}
sub print_cache_stats {
    say "cache hit/miss: $cache_hit/$cache_miss";
}



# sub selector ($) { eval 'sub { $_ ? $_->' . join ('', map "{$_}", split /\./, $_[0]) . ' : undef }' }
# sub selector_multi ($) { eval 'sub { [' . join(',', map { '($_ ? $_->' . join ('', map "{$_}", split /\./, $_) . ' : undef)' } split /,/, ($_[0] =~ s/\s+//gr)) . '] }' }
*selector = cached_single_arg(sub { eval 'sub { $_ ? $_->' . join ('', map "{$_}", split /\./, $_[0]) . ' : undef }' });
*selector_multi = cached_single_arg(sub { eval 'sub { [' . join(',', map { '($_ ? $_->' . join ('', map "{$_}", split /\./, $_) . ' : undef)' } split /,/, ($_[0] =~ s/\s+//gr)) . '] }' });

1;

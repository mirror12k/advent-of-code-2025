#!/usr/bin/env perl
package adventofcode;
use strict;
use warnings;

use feature qw/ say /;
use LWP::UserAgent;
use IO::File;
use Carp;

use base 'Exporter';
our @EXPORT = qw/
	get_challenge
	post_answer
/;

my $ua = LWP::UserAgent->new;
$ua->cookie_jar({});
$ua->cookie_jar->set_cookie(0, 'session', $ENV{SESSION_COOKIE}, '/', 'adventofcode.com');

sub readfile { local $/; my $file = IO::File->new($_[0], 'r'); <$file> }
sub writefile { local $/; my $file = IO::File->new($_[0], 'w'); $file->print($_[1]) }

sub get_cached_challenge {
	my ($path) = @_;

	$path =~ s#/#_#g;
	$path =~ s#\.#_#g;

	if (-f ".data/$path") {
		return readfile(".data/$path");
	}
}

sub put_cached_challenge {
	my ($path, $data) = @_;

	$path =~ s#/#_#g;
	$path =~ s#\.#_#g;

	writefile(".data/$path", $data);
}

sub get_challenge {
	my ($path) = @_;

	my $cached = get_cached_challenge($path);
	return $cached if $cached;

	my $res = $ua->get("https://adventofcode.com/$path");
	die "failed to request input: " . $res->decoded_content unless $res->is_success;
	my $input = $res->decoded_content;

	put_cached_challenge($path, $input);

	return $input;
}

sub post_answer {
	my ($path, $level, $answer) = @_;
	croak "path argument required" unless defined $path;
	croak "level argument required" unless defined $level;
	croak "answer argument required" unless defined $answer;
	# Create the HTTP POST request
	my $res = $ua->post("https://adventofcode.com/$path",
	    'Content-Type' => 'application/x-www-form-urlencoded',
	    Content        => "level=$level&answer=$answer",
	);

	my $content = $res->decoded_content;
	# warn "answer response: $content";

	return $content;
}

1;

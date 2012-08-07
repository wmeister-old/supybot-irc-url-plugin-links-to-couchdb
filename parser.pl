#!/usr/bin/perl
use File::Basename qw(dirname);
sub path { dirname(__FILE__)."/$_[0]"; }
use lib path('lib');
use POSIX qw(strftime);
use Mojo::DOM;
use URI::Escape qw(uri_unescape);
use HTML::Entities qw(encode_entities);
use strict;
use warnings;

use Data::Dumper; # TODO remove when done

sub fetch {
	my ($url, $flag) = @_;
	my @args = qw/-s -f -L -m 60 --proto =http,https --proto-redir =http,https/;
	push @args, $flag if defined $flag;
	push @args, $url;
	open my $out, "-|", 'curl', @args;
	my $content = join '', (<$out>);
	close $out;
	return $content;
}

my %urls = ();

while(<>) {
    my ($id, $rest) = split ':', $_, 2;
    next unless defined $id && defined $rest;

    my $url;
    ($url, $rest) = split ',', $rest, 2;
    next unless defined $url;
    my $q = substr $url, 0, 1;
    $url =~ s/^['"]+//;
    $url =~ s/['"]+$//;
    if($q eq "'") {
	$url =~ s/\\"/"/g;
    } else {
	$url =~ s/\\'/'/g;
    }

    my $timestamp = int(substr($rest, (length($rest) - 1 - rindex($rest, ',')) * -1));

    my $title = uri_unescape($url);
    my $header = fetch($url, '-I');
    if(index($header, 'Content-Type: text/html') != -1) {
	my $html = fetch($url);
	if($html ne '' && defined(my $dom_title = Mojo::DOM->new($html)->at('title'))) {
	    $title = $dom_title->text;
	}
    }
    $title = encode_entities($title);

    push @{$urls{$timestamp}}, {id => $id, url => $url, timestamp => $timestamp, title => $title};
}
# TODO sort keys %urls; genrate html
print Dumper([\%urls]);


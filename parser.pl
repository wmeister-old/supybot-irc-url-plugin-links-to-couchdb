#!/usr/bin/perl
use File::Basename qw(dirname);
sub path { dirname(__FILE__)."/$_[0]"; }
use lib path('lib');
use POSIX qw(strftime);
use Mojo::DOM;
use URI::Escape qw(uri_unescape);
use HTML::Entities qw(encode_entities);
use CouchDB::Client;
use strict;
use warnings;

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

sub has_string {
    my ($a, $e) = @_;
    foreach my $t (@$a) { return 1 if $e eq $t; }
    return 0;
}

my %urls = ();
my $db_name = 'basement_links';
my $design_name = '_design/link';
my $client = CouchDB::Client->new(uri => "http://127.0.0.1:5984/") or die "couldn't create CouchDB client";
$client->dbExists($db_name) or die "$db_name does not exist";
my $db = $client->newDB($db_name);
$db->designDocExists($design_name) or die "design doc $design_name does not exsist";
my @ids = map { $_->{value} } @{$db->newDesignDoc('_design/link')->retrieve->queryView('all_ids')->{rows}};

while(<>) {
    my ($id, $rest) = split ':', $_, 2;
    next unless defined $id && defined $rest;
    next if has_string(\@ids, $id);

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
    
    $db->newDoc($id, undef, {id => $id, escaped_url => $url, timestamp => $timestamp, encoded_title => $title})->create;
}



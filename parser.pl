#!/usr/bin/perl
use File::Basename qw(dirname);
sub path { dirname(__FILE__)."/$_[0]"; }
use lib path('lib');
use POSIX qw(strftime);
use Mojo::DOM;
use URI::Escape qw(uri_unescape);
use HTML::Entities qw(encode_entities);
use CouchDB::Client;
use File::Temp;
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
    0;
}
sub has_mime_type {
    my ($header, $type) = @_;
    index($header, "Content-Type: $type") != -1;
}

my %urls = ();
my $db_name = 'basement_links';
my $design_name = '_design/link';
my $client = CouchDB::Client->new() or die "couldn't create CouchDB client";
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
    if(has_mime_type($header, 'text/html')) {
	my $html = fetch($url);
	if($html ne '' && defined(my $dom_title = Mojo::DOM->new($html)->at('title'))) {
	    $title = $dom_title->text;
	}
    }
    $title = encode_entities($title);

    my $doc = {id => $id,
	       type => 'unknown', 
	       escaped_url => $url,
	       timestamp => $timestamp, 
	       encoded_title => $title};
    my $content = undef;
    if(has_mime_type($header, 'image/jpeg') 
       || has_mime_type($header, 'image/gif')
       || has_mime_type($header, 'image/png')) {
	my $fh = File::Temp->new();	
	print $fh $content = fetch($url);
	my $name = $fh->filename;
	my $type = `file -i $name`;
	if($type =~ m!image/(jpeg|png|gif|);!i) {
	    $doc->{type} = 'image';
	    $doc->{mime_type} = "image/$1";
	}
    }

    my $saved_doc = $db->newDoc($id, undef, $doc)->create();
    $saved_doc->addAttachment("image", $doc->{mime_type}, $content)->update() if $doc->{type} eq 'image';
}

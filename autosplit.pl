#!/usr/bin/perl --

# AutoSplit
# Copyright (c) 2002 wlindley.com, l.l.c.   http://www.wlindley.com
#
# Parse an HTML file which will serve both as a template and as
# the content for a website (or a portion of a website).  Find the
# <DIV> with ID="content", and use the <DIV> tags nested therein
# as the content.  The <DIV STYLE="filename=foo"> will output either
# foo/index.html (if that DIV contains other DIV tags) or foo.html.
#
# Written and maintained by William Lindley   wlindley@wlindley.com
#

use File::Basename;

use URI::URL;
use Cwd;

BEGIN {
    push @INC, dirname($0); # so we can find our own modules
}

use TransientBaby;
use TransientTreeBuilder;

my $VERSION = "0.3";
my $DATE =    "4 November 2003";

print "AutoSplit Version $VERSION  $DATE  (c) Copyright 2003 wlindley.com, l.l.c.\n";

undef $/;

$base = $ARGV[0]; # First file is actual base, possibly with path

unless (-e $base) {
    die "Cannot open input file '$base'\n";
}
unless (-T $base) {
    die "$base is not a text file.\n";
}

print "Reading $base [$true_base]\n";

open FILE, $base;
$text = <FILE>;
close FILE;

$text =~ s/<![a-zA-Z]+[^>]*>//;  # Remove offensive XML-ish tag foolishness

my $h = new TransientTreeBuilder; 

$h->ignore_unknown(0);
$h->warn(1);
$h->implicit_tags(0);
$h->parse($text);


my $template = TransientTreeBuilder->new($h->{root});

# Example of setting a META tag in the HEAD.
{
    my $generator = $template->{root}->find({tag => 'meta', name => 'generator'});
    unless ($generator) {
	$generator = TransientHTMLTreeNode->new();
	my $head = $template->{root}->find({tag => 'head'});
	$head->append_sibling($generator);
    }
    $generator->set_attribs({tag => meta, name => 'generator', content => "AutoSplit Version $VERSION"});
}


my $content = $template->{root}->find({tag => 'div', id => 'content'});
#$content->attr('style', 'blort: foo');
$content->delete_content(1); # delete all content

my $testnode = TransientHTMLTreeNode->new();
$testnode -> set_attribs ({tag => 'img', src => 'http://www.wlindley.com/logo.jpg'});
$content->push_content('blort!');
$content->push_content($testnode);
$content->unshift_content('foo!');

print "--------------\n";
print $template->regen();
print "--------------\n";

1;

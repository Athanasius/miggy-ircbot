#!/usr/bin/perl -w -Imodules -Ishare/perl/5.14.2
use strict;
use warnings;

use Data::Dumper;
#use WWW::Mechanize;

#my $mech = WWW::Mechanize->new();
#$mech->get('http://www.youtube.com/watch?v=9612CgOr3lE');
#
#printf "Title: %s\n", $mech->title;

use HTML::TreeBuilder;

my $tree = HTML::TreeBuilder->new;
my $page = "";
while (<STDIN>) {
  $page = $page . $_;
}
$tree->parse($page);
$tree->eof();
$tree->elementify();
print Dumper($tree);

my $title = $tree->look_down('_tag', 'title');
if ($title) {
  printf "Title: '%s'\n", $title->as_text;
} else {
  print "No title!\n";
}

#$tree->dump;
$tree->delete;

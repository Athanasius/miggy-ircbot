#!/usr/bin/perl -w

use strict;

my $mynick = '^Lumi^';
my $rmessage = \ '^Lumi^: seen AthanFysh';

if ($$rmessage =~ /^(?:\Q$mynick\E[,:])?\s*seen\s+([^ ]+)/) {
	print $$rmessage, "\n";
} else {
	print "No match\n";
}

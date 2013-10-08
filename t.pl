#!/usr/bin/perl -w -Imodules -Ishare/perl/5.14.2
use strict;
use warnings;

use Data::Dumper;

my @steps = (50, 25, 15, 5, 1, 1, 1, 1);

my $current = 2099732845;
my $t = 2099900000;
while (@steps and $current < $t) {
  my $s = pop @steps;
  printf STDERR "\tStep: %d\n", $s;
  $t -= 100000 * $s;
  printf STDERR "\tProposing: %d\n", $t;
}
  while ($current < $t) {
        $t -= 10000000; # Drop another 100k
        printf STDERR "\tProposing: %d\n", $t;
          }

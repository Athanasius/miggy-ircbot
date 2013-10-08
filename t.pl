#!/usr/bin/perl -w -Imodules -Ishare/perl/5.14.2
use strict;
use warnings;

use Data::Dumper;

use POSIX qw/strftime/;

my $dayofweek = 'Fri';
my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
my @today = grep { $days[$_] eq $dayofweek } 0..$#days;

print Dumper(@today), "\n";

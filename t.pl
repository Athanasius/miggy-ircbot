#!/usr/bin/perl -w -Imodules

use strict;
use Data::Dumper;
use SCIrcBot::Crowdfund;

my $cf = new SCIrcBot::Crowdfund;

#$cf->{last_cf} = { 'time' => time(),
#  'funds' => 2099940000,
#  'fans' => 276999,
#  'alpha_slots_left' => 10326
#}

print $cf->next_funds_threshold(2079940000), "\n";

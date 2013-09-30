#!/usr/bin/perl -w -Imodules

use strict;
use Data::Dumper;
#use SCIrcBot::ConfigFile;
use SCIrcBot::Crowdfund;

#my $config = SCIrcBot::ConfigFile->new(file => "bot-config.text");
#print Dumper($config);

my $cf = new SCIrcBot::Crowdfund;

print Dumper($cf);
print $cf->get_current_cf, "\n";

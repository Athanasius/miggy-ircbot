#!/usr/bin/perl -w

use strict;
use LWP::UserAgent;

my $ua = LWP::UserAgent->new;
print STDERR "Getting https://community.elitedangerous.com/galnet/uid/56a60d089657ba197a730a88...\n";
my $res = $ua->get('https://community.elitedangerous.com/galnet/uid/56a60d089657ba197a730a88');
print STDERR "Done\n";
print $res->content, "\n";

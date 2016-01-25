#!/usr/bin/perl -w

use strict;
use Net::HTTPS;

my $nethttp = Net::HTTPS->new(Host => 'community.elitedangerous.com', KeepAlive => 1);
print STDERR "Getting https://community.elitedangerous.com/galnet/uid/56a60d089657ba197a730a88...\n";
my $req = $nethttp->format_request('GET', '/galnet/uid/56a60d089657ba197a730a88');
printf STDERR "Request: '%s'\n", $req;
if (! $nethttp->write_request('GET', '/galnet/uid/56a60d089657ba197a730a88')) {
  die("write_request failed\n");
}
print STDERR "Done\n";
my ($code, $mess, %headers) = $nethttp->read_response_headers();
if ($code != 200) {
  print STDERR "Didn't get a 200 response\n";
  printf STDERR "Code: %d\n", $code;
}
my $buf;
my $n = $nethttp->read_entity_body($buf, 4096);
while (defined($n) and $n > 0) {
  print $buf;
  $n = $nethttp->read_entity_body($buf, 4096);
}

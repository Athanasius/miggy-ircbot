#!/usr/bin/perl -w
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab
# 
# Use RSI API JSON query to fetch all new dev posts and then update/create
# an RSS file for that data.

use strict;

use LWP;
use HTTP::Request;
use JSON;
use HTML::TreeBuilder;

use DBI;
use DBD::SQLite;

my $ua = new LWP::UserAgent(agent => 'ua-scircbot');
## As of 2013-11-28 the JSON call can't retrieve page 0 so we'll just have
## to retrieve the RSI front page and parse it.


## And now start going through older posts until we find one we already know.
my $json = encode_json(
  {
    'page' => '1'
  }
);
print "Request JSON: '", $json, "'\n";
my $req = HTTP::Request->new('POST', 'https://robertsspaceindustries.com/api/hub/getTrackedPosts');
$req->header('Content-Type' => 'application/json');
$req->content($json);
my $res = $ua->request($req);
if (! $res->is_success) {
  die("Error retrieving from getTrackedPosts: " . $res->status_line);
}

if ($res->content !~ /^{".*}$/) {
  die("Returned content not in JSON format: '" . $res->content . "'");
}

$json = decode_json($res->content);

foreach my $k (keys(%$json)) {
  printf "Key in data: %s\n", $k;
  printf "  %s\n", ${$json}{$k};
}



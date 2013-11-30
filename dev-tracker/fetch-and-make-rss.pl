#!/usr/bin/perl -w
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab
# 
# Use RSI API JSON query to fetch all new dev posts and then update/create
# an RSS file for that data.

use strict;
use Data::Dumper;

use LWP;
use HTTP::Request;
use JSON;
use HTML::TreeBuilder;

use DBI;
use DBD::SQLite;

my $ua = new LWP::UserAgent(
  agent => 'ua-scircbot',
  cookie_jar => { file => 'lumi-sc-cookies.jar' }
);
## First things first, check if we're logged in, so load the 'My RSI' page
my $req = HTTP::Request->new('GET', 'https://robertsspaceindustries.com/account/settings');
my $res = $ua->request($req);
if (! $res->is_success) {
  die("Error retrieving My RSI page: " . $res->status_line);
}
## We'll use whether or not our email address shows up to determin if logged in
if ($res->content !~ /lumi-sc\@miggy\.org/) {
  printf STDERR "Not logged in, so doing that ...\n";
  $req = HTTP::Request->new('POST', 
  # Form has:
  # <input type="text" name="login_id" value="" class="trans-02s trans-color trans-box-shadow" id="signin_input_loginid">
  # <input type="password" name="password" value="" class="trans-02s trans-color trans-box-shadow" id="signin_input_password">
}

exit(0);

## As of 2013-11-28 the JSON call can't retrieve page 0 so we'll just have
## to retrieve the RSI front page and parse it.
$req = HTTP::Request->new('GET', 'https://robertsspaceindustries.com/');
$res = $ua->request($req);
if (! $res->is_success) {
  die("Error retrieving RSI front page: " . $res->status_line);
}

my $tree = HTML::TreeBuilder->new;
$tree->parse($res->decoded_content);
$tree->eof();

my $dev_tracker = $tree->look_down("class", "devtracker-list");
if (!defined($dev_tracker)) {
  die("Couldn't find devtracker-list");
}
#print Dumper($dev_tracker->content_list());
my @dev_a = $dev_tracker->look_down("class", "devtracker  content-block3");
if (! @dev_a) {
  die("Couldn't extract array of devtracker elements");
}
foreach my $a (@dev_a) {
  print $a->attr('href'), "\n";
## So, now go fetch the URL and get all the data from there ?
## Else what we have right here is:
##  The URL to get a browser to this post
##  Poster handle and title
##  Post excerpt
##  Textual post age, i.e. "9 hours ago"
##  Thread title
  my $req = HTTP::Request->new('GET', $a->attr('href'));
  my $res = $ua->request($req);
  if (! $res->is_success) {
    printf STDERR "Error retrieving URL '%s': %s\n", $a->attr('href'), $res->status_line;
    next;
  }

  print $res->decoded_content;

  next;
  my $tree = HTML::TreeBuilder->new;
  $tree->parse($res->decoded_content);
  $tree->eof();
}


##
exit(0);


## And now start going through older posts until we find one we already know.
my $json = encode_json(
  {
    'page' => '1'
  }
);
print "Request JSON: '", $json, "'\n";
$req = HTTP::Request->new('POST', 'https://robertsspaceindustries.com/api/hub/getTrackedPosts');
$req->header('Content-Type' => 'application/json');
$req->content($json);
$res = $ua->request($req);
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



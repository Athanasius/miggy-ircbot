#!/usr/bin/perl -w -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;
use POE;
use POE::Component::Client::HTTP;
use HTTP::Request;
use POSIX qw/strftime/;

POE::Component::Client::HTTP->spawn(
  Alias       => 'bugtest',
  Agent       => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
);
POE::Session->create(inline_states => {
  _start => sub { $_[KERNEL]->yield('request_galnet') },
  request_galnet => \&request_galnet,
  response => \&response_handler }
);


sub response_handler {
  my ($req, $response) = @_[ARG0, ARG1];
  my $res = $response->[0];

  if (! $res->is_success) {
    my $error = "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    warn(strftime("%Y-%m-%d %H:%M:%S %z - ", localtime(time())), $error);
    return undef;
  }

  if ($res->header('Content-Type') =~ /^text\/(ht|x)ml/) {
    print(strftime("%Y-%m-%d %H:%M:%S %z - ", localtime(time())), "URL successfully retreived\n");
    exit(0);
  } else { 
    
    print(strftime("%Y-%m-%d %H:%M:%S %z - ", localtime(time())), "That was not an HTML page\n");
  } 
}

sub request_galnet {
  my $req = HTTP::Request->new('GET', 'https://community.elitedangerous.com/galnet/uid/56a60d089657ba197a730a88'); #, [ "Connection" => "close" ]);
  print(strftime("%Y-%m-%d %H:%M:%S %z - ", localtime(time())), "Posting request...\n");
  $_[KERNEL]->post( 'bugtest', 'request', 'response', $req);
}

POE::Kernel->run();

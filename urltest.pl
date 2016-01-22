#!/usr/bin/perl -w -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;
use POE;
use POE::Component::IRC;
use MiggyIRCBot::ConfigFile;
use MiggyIRCBot::URLParse;
use POSIX qw/strftime/;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}

my $irc = POE::Component::IRC->spawn();

POE::Session->create(
  package_states => [
    main => [ qw( _default _start
      irc_miggybot_url_success irc_miggybot_url_error
      ) ]
  ],
  inline_states => {
  }
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

  $irc->plugin_add('MiggyIRCBotURLParse',
    MiggyIRCBot::URLParse->new(
            youtube_api_key => $config->getconf('youtube_api_key'),
            imgur_clientid => $config->getconf('imgur_clientid'),
            imgur_clientsecret => $config->getconf('imgur_clientsecret')
    )
  );

  $kernel->yield('get_url', { _channel => "#test", session => $session, quiet => 0, url => $ARGV[0] } );
}

###########################################################################
# URL Parsing
###########################################################################
sub irc_miggybot_url_success {
  my ($kernel,$sender,$args,$title) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $channel = delete $args->{_channel};

#printf STDERR "irc_miggybot_url_success:\n";
  if (defined($_[ARG1]) and $_[ARG1] ne "" and $args->{quiet} == 0) {
    my $blurb = $_[ARG1];
    print $blurb, "\n";
  }
  exit(0);
}

sub irc_miggybot_url_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_miggybot_url_error...");
  print $error, "\n";
  exit(0);
}
###########################################################################

sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "$event: " );

    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        } elsif (defined($arg)) {
            push ( @output, "'$arg'" );
        }
    }
    mylog(join ' ', @output);
    return;
}

sub mylog {
  printf STDERR "%s - %s\n", strftime("%Y-%m-%d %H:%M:%S UTC", gmtime()), @_;
}

#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;

use POE;
use POE::Component::IRC::Qnet::State;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Console;
use POE::Component::IRC::Plugin::Seen;
use POE::Component::IRC::Plugin::BotCommand;

use SCIrcBot::Crowdfund;
use SCIrcBot::ConfigFile;
use SCIrcBot::RSS;
use POSIX;
use Data::Dumper;

my $config = SCIrcBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}

my $crowdfund;
my $rss_url = 'https://robertsspaceindustries.com/comm-link/rss';

my $irc = POE::Component::IRC::Qnet::State->spawn();

POE::Session->create(
  package_states => [
    main => [ qw(_default _start
      irc_join
      irc_botcmd_crowdfund
      irc_botcmd_rss
      irc_botcmd_r
      irc_console_service irc_console_connect irc_console_authed irc_console_close irc_console_rw_fail
      irc_rssheadlines_items
      irc_rssheadlines_error
      ) ]
  ],
  inline_states => {
    crowdfund_check_threshold => \&handle_crowdfund_check_threshold,
  }
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap) = @_[KERNEL ,HEAP];

  $irc->plugin_add('BotCommand',
    POE::Component::IRC::Plugin::BotCommand->new(
      Commands => {
        crowdfund => { 
          info => 'Takes no arguments, reports current crowdfund data.',
          aliases => [ 'cf' ],
        },
        rss => {
          info => 'Takes no arguments, checks RSI RSS feed.',
        },
        r => {
          info => 'Testing kernel->post',
        },
      },
      In_channels => 1,
      Addressed => 0,
      Prefix => '!',
      Method => 'privmsg',
    )
  );

  $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
  $irc->plugin_add( 'Connector' => $heap->{connector} );

  $irc->yield ( connect => {
      Nick => $config->getconf('nickname'),
      Server => $config->getconf('ircserver'),
      Port => $config->getconf('ircport'),
      Ircname => $config->getconf('ircname'),
    }
  );

  $irc->plugin_add( 'Console',
    POE::Component::IRC::Plugin::Console->new(
      bindport => $config->getconf('console_port'),
      password => $config->getconf('console_password'),
    )
  );
  $irc->plugin_add('AutoJoin',
    POE::Component::IRC::Plugin::AutoJoin->new(
      Channels => [ $config->getconf('channel') ]
    )
  );
  $irc->plugin_add('Seen',
    POE::Component::IRC::Plugin::Seen->new(
      filename => $config->getconf('seen_filestore')
    )
  );

  $irc->plugin_add('RSSHead',
    POE::Component::IRC::Plugin::RSS::Headlines->new()
  );
  $irc->yield(register => 'all');

  # Initialise CrowdFund module
  $crowdfund = new SCIrcBot::Crowdfund;
  # And set up the delayed check
  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));
}

sub irc_kill {
  my $server = $_[ARG0];
  my $nick = $_[ARG1];
  my $reason = $_[ARG2];

  return;
}

sub irc_join {
  my $nick = (split /!/, $_[ARG0])[0];
  my $channel = $_[ARG1];
  my $irc = $_[SENDER]->get_heap();

  #printf "irc_join - Nick: '%s', Channel: '%s'\n", $nick, $channel;
  # only send the message if we were the one joining
  if ($nick eq $irc->nick_name()) {
    #print "irc_join - It's me! Sending greeting...\n";
    $irc->yield(privmsg => $channel, 'Reporting for duty!');
  }
}

sub irc_public {
  my $nick = (split /!/, $_[ARG0])[0];
  my $channel = $_[ARG1];
  my $msg = $_[ARG2];
  my $irc = $_[SENDER]->get_heap();
}

###########################################################################
# Crowdfund related functions
###########################################################################
### The in-channel checking of crowdfund
sub irc_botcmd_crowdfund {
  my $channel = $_[ARG1];

  $irc->yield('privmsg', $channel, $crowdfund->get_current_cf());
}

### Function to check current/last crowdfund against thresholds
sub handle_crowdfund_check_threshold {
  my $kernel = $_[KERNEL];

  my $cf_check = $crowdfund->check_crowdfund();
  if (defined($cf_check)) {
    $irc->yield('privmsg', $config->getconf('channel'), $cf_check);
  }

  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));
}
###########################################################################

###########################################################################
# RSS Checking
###########################################################################
sub irc_botcmd_rss {
  my ($kernel, $session, $channel) = @_[KERNEL, SESSION, ARG1];

  $irc->yield('privmsg', $channel, "Running RSS query, please wait ...");
printf STDERR "$channel $rss_url\n";
  $kernel->yield('get_headline', { url => $rss_url, _channel => $channel, session => $session } );
  $irc->yield('privmsg', $channel, "Ran RSS query (still waiting for results?)");
}

sub irc_botcmd_r {
  my ($kernel, $session, $channel) = @_[KERNEL, SESSION, ARG1];

  $irc->yield('privmsg', $channel, "r -> Attempting to fire !crowdfund instead...");
  my @params;
  push @params, $session, 'irc_botcmd_crowdfund', '', $channel;
printf STDERR "\@params ->\n"; for my $p (@params) { print $p, ", "; } print "\n";
  $kernel->post( @params );
  return;
}

sub irc_rssheadlines_items {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

mylog("irc_rssheadlines_items: channel: $channel, #items: $#_");
  $irc->yield('privmsg', $channel, join(' ', @_[ARG1..$#_] ) );
}

sub irc_rssheadlines_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_rssheadlines_error...");
  $kernel->post($sender, 'privmsg', $channel, "RSS Error: " . $error);
}
###########################################################################

sub irc_console_service {
  my $getsockname = $_[ARG0];
  return;
}

sub irc_console_connect {
  my ($peeradr, $peerport, $wheel_id) = @_[ARG0 .. ARG2];
  return;
}

sub irc_console_authed {
  my $wheel_id = $_[ARG0];
  return;
}

sub irc_console_close {
  my $wheel_id = $_[ARG0];
  return;
}

sub irc_console_rw_fail {
  my ($peeradr, $peerport) = @_[ARG0, ARG1];
  return;
}

sub _default {
    my ($event, $args) = @_[ARG0 .. $#_];
    my @output = ( "$event: " );

    for my $arg (@$args) {
        if ( ref $arg eq 'ARRAY' ) {
            push( @output, '[' . join(', ', @$arg ) . ']' );
        }
        elsif (defined($arg)) {
            push ( @output, "'$arg'" );
        }
    }
    mylog(join ' ', @output);
    return;
}

sub mylog {
  printf STDERR "%s - %s\n", strftime("%Y-%m-%d %H:%M:%S UTC", gmtime()), @_;
}

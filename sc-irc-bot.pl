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

my $irc = POE::Component::IRC::Qnet::State->spawn();

POE::Session->create(
  package_states => [
    main => [ qw(_default _start
      irc_join
      irc_botcmd_crowdfund
      irc_sc_crowdfund_success
      irc_sc_crowdfund_error
      irc_botcmd_rss
      irc_sc_rss_newitems
      irc_sc_rss_error
      irc_console_service irc_console_connect irc_console_authed irc_console_close irc_console_rw_fail
      ) ]
  ],
  inline_states => {
    #crowdfund_check_threshold => \&handle_crowdfund_check_threshold,
    rss_check => \&handle_rss_check,
  }
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

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

  $irc->plugin_add('SCRSS',
    SCIrcBot::RSS->new(
      rss_url => $config->getconf('rss_url'),
      rss_file => $config->getconf('rss_filestore')
    )
  );
  $kernel->delay('rss_check', $config->getconf('rss_check_time'));

  $irc->plugin_add('SCCrowdfund',
    SCIrcBot::Crowdfund->new()
  );
  #$kernel->yield('get_crowdfund', { _channel => $config->getconf('channel'), session => $session, quiet => 1 } );

  $irc->yield( register => 'all' );

  # And set up the delayed check
# XXX:  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));
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


###########################################################################
# Crowdfund related functions
###########################################################################
### The in-channel checking of crowdfund
sub irc_botcmd_crowdfund {
  my ($kernel, $session, $channel) = @_[KERNEL, SESSION, ARG1];

  $irc->yield('privmsg', $channel, "Running crowdfund query, please wait ...");
  $kernel->yield('get_crowdfund', { _channel => $channel, session => $session, quiet => 0 } );
}

### Function to check current/last crowdfund against thresholds
sub handle_crowdfund_check_threshold {
  my $kernel = $_[KERNEL];

  #$kernel->yield('get_crowdfund', { _channel => $config->getconf('channel'), session => $session, quiet => 1 } );

  #$kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));
}

sub irc_sc_crowdfund_success {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

printf STDERR "irc_sc_crowdfund_success:\n";
  if (defined($_[ARG1])) {
    my $crowd = $_[ARG1];
    if (defined(${$crowd}{'error'})) {
      $irc->yield('privmsg', $channel, ${$crowd}{'error'});
    } elsif (defined(${$crowd}{'report'})) {
      $irc->yield('privmsg', $channel, ${$crowd}{'report'});
    }
  }
}

sub irc_sc_crowdfund_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_sc_crowdfund_error...");
  $irc->yield('privmsg', $channel, "Crowdfund Error: " . $error);
}
###########################################################################

###########################################################################
# RSS Checking
###########################################################################
sub handle_rss_check {
  my ($kernel, $session) = @_[KERNEL, SESSION];

  $kernel->yield('get_rss_items', { _channel => $config->getconf('channel'), session => $session, quiet => 1 } );

  $kernel->delay('rss_check', $config->getconf('rss_check_time'));
}

sub irc_botcmd_rss {
  my ($kernel, $session, $channel) = @_[KERNEL, SESSION, ARG1];

  $irc->yield('privmsg', $channel, "Running RSS query, please wait ...");
  $kernel->yield('get_rss_items', { _channel => $channel, session => $session, quiet => 0 } );
}

sub irc_sc_rss_newitems {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

  if (defined($_[ARG1])) {
    for my $i (@_[ARG1..$#_]) {
      $irc->yield('privmsg', $channel, 'New Comm-Link: "' . $i->{'title'} . '" - ' . $i->{'permaLink'});
    }
  } elsif (! $args->{quiet}) {
      $irc->yield('privmsg', $channel, 'No new Comm-links at this time');
  }
}

sub irc_sc_rss_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_sc_rss_error...");
  $irc->yield('privmsg', $channel, "RSS Error: " . $error);
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

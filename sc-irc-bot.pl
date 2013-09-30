#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;

use POE;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Qnet::State;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Console;
use POE::Component::IRC::Plugin::Seen;
use SCIrcBot::Crowdfund;
use ConfigFile;
use POSIX;
use Data::Dumper;

my $config = SCIrcBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}

my $crowdfund;

my $irc = POE::Component::IRC::Qnet::State->spawn();

POE::Session->create(
  package_states => [
    main => [ qw(_default _start
      irc_join
      irc_public
      irc_console_service irc_console_connect irc_console_authed irc_console_close irc_console_rw_fail) ]
  ]
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap) = @_[KERNEL ,HEAP];

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

  $irc->yield(register => 'all');
  $irc->yield('connect' => { } );

  # Initialise CrowdFund module
  $crowdfund = new SCIrcBot::Crowdfund;
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

  if ($msg =~ /^!crowdfund$/ || $msg =~ /^!cf$/) {
    report_crowdfund($nick, $channel);
  }
}

sub report_crowdfund {
}

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
        else {
            push ( @output, "'$arg'" );
        }
    }
    print join ' ', @output, "\n";
    return;
}

sub mylog {

  printf "%s - %s\n", strftime("%Y-%m-%d %H:%M:%S UTC", gmtime()), @_;
}

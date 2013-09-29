#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;

use POE;
use POE::Component::IRC::Qnet::State;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Console;
use POE::Component::IRC::Plugin::Seen;
use ConfigFile;

my $config = SCIrcBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}
my $irc;
my $lastconnattempt = time() - $config->getconf('connect_delay');

POE::Session->create(
  package_states => [
    main => [ qw(_default _start
      irc_join
      irc_disconnected
      irc_console_service irc_console_connect irc_console_authed irc_console_close irc_console_rw_fail) ]
  ]
);

$poe_kernel->run();

sub _start {
  connect_to_server();
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

}

sub connect_to_server {
  my $kernel = shift;
  my $session = shift;

  if ((time() - $lastconnattempt) < $config->getconf('connect_delay')) {
    sleep($config->getconf('connect_delay'));
  }
  $lastconnattempt = time();
  $irc = POE::Component::IRC::Qnet::State->spawn(
    Nick => $config->getconf('nickname'),
    Server => $config->getconf('ircserver'),
    Port => $config->getconf('ircport'),
    Ircname => $config->getconf('ircname'),
  ) or die "Failed to spawn IRC connection";
}

sub irc_disconnected {
  my $server = $_[ARG0];


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

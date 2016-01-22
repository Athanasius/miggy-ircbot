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

use MiggyIRCBot::ConfigFile;
use MiggyIRCBot::RSS;
use MiggyIRCBot::URLParse;
use MiggyIRCBot::AlarmClock;
use POSIX qw/strftime/;
use Data::Dumper;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}

my $irc = POE::Component::IRC::Qnet::State->spawn();

POE::Session->create(
  package_states => [
    main => [ qw(_default _start irc_001
      irc_join
      irc_public
      irc_ctcp_action
      irc_invite
      irc_miggybot_url_success irc_miggybot_url_error
      irc_botcmd_rss irc_miggybot_rss_newitems irc_miggybot_rss_error irc_miggybot_rss_latest
      irc_botcmd_alarm irc_miggybot_alarm_announce
      irc_botcmd_youtube
      irc_botcmd_twitch
      irc_botcmd_community_site
      irc_console_service irc_console_connect irc_console_authed irc_console_close irc_console_rw_fail
      ) ]
  ],
  inline_states => {
    crowdfund_check_threshold => \&handle_crowdfund_check_threshold,
    rss_check => \&handle_rss_check,
  }
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

  $irc->plugin_add('BotCommand',
    POE::Component::IRC::Plugin::BotCommand->new(
      Commands => {
        rss => {
          info => "With no argument checks Athanasius' Unofficial Frontier Dev Forum Posts RSS feed (OPS/VOICE ONLY).  With \"latest\" as argument it will repeat the latest posted item details (anyone).",
        },
        youtube => {
          info => "Displays FD YouTube channel URL"
        },
        twitch => {
          info => "Displays FD Twitch.TV channel URL"
        },
        community_site => {
          info => "Displays the URL for the ED Community site",
          aliases => [ 'commsite', 'community' ]
        },
      },
      In_channels => 1,
      Addressed => 0,
      Prefix => '!',
      Method => 'privmsg',
      Ignore_unknown => 1,
      Eat => 1,
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

  $irc->plugin_add('MiggyIRCBotRSS',
    MiggyIRCBot::RSS->new(
      rss_url => $config->getconf('rss_url'),
      rss_file => $config->getconf('rss_filestore')
    )
  );
  $kernel->delay('rss_check', $config->getconf('rss_check_time'));

  $irc->plugin_add('MiggyIRCBotURLParse',
    MiggyIRCBot::URLParse->new()
  );

  $irc->plugin_add('MiggyIRCBotAlarmClock',
    MiggyIRCBot::AlarmClock->new()
  );
  $kernel->yield('init_alarms', { session_id => $session });

  $irc->yield( register => 'all' );
}

###########################################################################
# Responding to IRC events
###########################################################################
sub irc_001 {
  my ($kernel, $sender) = @_[KERNEL, SENDER];
  my $irc = $_[SENDER]->get_heap();

  print " irc_001:\n";

  # Set mode +x
  print " Attempt to set usermode +x\n";
  $irc->yield('mode', $config->getconf('nickname') . " +x");

  # Lets authenticate with Quakenet's Q bot
  my $qauth = $config->getconf('qauth');
  my $qpass = $config->getconf('qpass');
  if (defined($qauth) and $qauth ne '' and defined($qpass) and $qpass ne '') {
    print "  Qauth and Qpass appear set. Attempting Q Auth...\n";
    $kernel->post( $sender => qbot_auth => $config->getconf('qauth') => $config->getconf('qpass') );
  }

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

#irc_invite
sub irc_invite {
  my $nick = (split /!/, $_[ARG0])[0];
  my $channel = $_[ARG1];
  my $irc = $_[SENDER]->get_heap();

  printf "irc_invite - Nick: '%s', Channel: '%s'\n", $nick, $channel;
  if ($channel eq $config->getconf('channel')) {
    print " irc_invite: For our channel\n";
    my $on_channel = undef;
    foreach my $c ( keys %{$irc->channels()} ) {
      if ($c eq $config->getconf('channel')) {
        print " irc_invite: We're currently on our channel\n";
        $on_channel = $c;
        last;
      }
    }
    if (!defined($on_channel)) {
      printf " irc_invite: Not currently on configured channel, attempting to join '%s'\n", $channel;
      $irc->yield(join => $channel);
    }
  }
}

#irc_public:  'Athan!athan@hako.miggy.org' [#sc] '!url https://t.co/zugfxL6F91'
sub irc_public {
  my ($kernel, $session, $channel, $msg) = @_[KERNEL, SESSION, ARG1, ARG2];

  lookup_url_title($kernel, $channel, $session, $msg);
}

#irc_ctcp_action:  'Athan!athan@hako.miggy.org' [#sc] 'tests with https://twitter.com/'
sub irc_ctcp_action {
  my ($kernel, $session, $channel, $msg) = @_[KERNEL, SESSION, ARG1, ARG2];

  lookup_url_title($kernel, $channel, $session, $msg);
}

sub lookup_url_title {
  my ($kernel, $channel, $session, $msg) = @_;

  my $url;
  if ($msg =~ /(^|[\s,.!\?:]+)(?<url>http[s]{0,1}:\/\/[^\/]+\/[^\s]*)([\s,.!\?:]+|$)/) {
    $url = $+{'url'};
  }
  if (defined($url) and $url =~ /(?<url>.*)[\.,\?:!]+$/) {
    $url = $+{'url'};
  }
  if (defined($url)) {
printf STDERR "irc_public/action: parsed '\n%s\n' from '\n%s\n', passing to get_url...\n", $url, $msg;
    $kernel->yield('get_url', { _channel => $channel, session => $session, quiet => 0, url => $url } );
  }
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
  my ($kernel, $session, $sender, $channel, $arg) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  if (defined($arg)) {
    if ($arg eq "latest") {
      $kernel->yield('get_rss_latest', { _channel => $channel, session => $session, quiet => 0 } );
    }
  } else {
    unless ($poco->is_channel_operator($channel, $nick)
      or $poco->has_channel_voice($channel, $nick)) {
      return;
    }
    $irc->yield('privmsg', $channel, "Running RSS query, please wait ...");
    $kernel->yield('get_rss_items', { _channel => $channel, session => $session, quiet => 0 } );
  }
}

sub irc_miggybot_rss_newitems {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

  if (defined($_[ARG1])) {
    for my $i (@_[ARG1..$#_]) {
      $irc->yield('privmsg', $channel, 'New from RSS: "' . $i->{'title'} . '" - ' . $i->{'permaLink'});
    }
  } elsif (! $args->{quiet}) {
      $irc->yield('privmsg', $channel, 'No new RSS items at this time');
  }
}

sub irc_miggybot_rss_latest {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST\n";
  for my $i (@_[ARG1..$#_]) {
#printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST: Spitting out item\n";
    $irc->yield('privmsg', $channel, 'Latest RSS item: "' . $i->{'title'} . '" - ' . $i->{'guid'});
  }
}

sub irc_miggybot_rss_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_miggybot_rss_error...");
  $irc->yield('privmsg', $channel, "RSS Error: " . $error);
}
###########################################################################

###########################################################################
# URL Parsing
###########################################################################
sub irc_miggybot_url_success {
  my ($kernel,$sender,$args,$title) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $channel = delete $args->{_channel};

#printf STDERR "irc_miggybot_url_success:\n";
  if (defined($_[ARG1]) and $args->{quiet} == 0) {
    my $title = $_[ARG1];
    $irc->yield('privmsg', $channel, "URL Title: " . $title);
  }
}

sub irc_miggybot_url_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_miggybot_url_error...");
  $irc->yield('privmsg', $channel, $error);
}
###########################################################################

###########################################################################
# Informational commands
###########################################################################
# Youtube
sub irc_botcmd_youtube {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "Frontier Developments' YouTube channel is at: https://www.youtube.com/user/FrontierDevelopments");
}
# Twitch.TV
sub irc_botcmd_twitch {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "Frontier Developments' Twitch.TV channel is at: http://www.twitch.tv/frontierdev");
}
sub irc_botcmd_community_site {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "The (still beta?) Elite Dangerous Community site can be found at: https://community.elitedangerous.com/");
}
###########################################################################

###########################################################################
# Alarm Clock
###########################################################################
sub irc_botcmd_alarm {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  unless ($poco->is_channel_operator($channel, $nick)
    or $poco->has_channel_voice($channel, $nick)) {
    return;
  }

  $irc->yield('privmsg', $channel, "Alarm test command");
}

sub irc_miggybot_alarm_announce {
  my ($kernel, $sender, $alarmtag, $alarm, $pre) = @_[KERNEL, SENDER, ARG0, ARG1, ARG2];
  my $channel = $config->getconf('channel');

  #printf STDERR "irc_miggybot_alarm_announce: alarm = %s\n", Dumper($alarm);
  if (defined($pre)) {
    $irc->yield('privmsg', $channel, sprintf(${$alarm}{'pre_announce_text'}, hours_minutes_text($pre)));
  } else {
    $irc->yield('privmsg', $channel, ${$alarm}{'announce_text'});
  }

  undef;
}

# Given a number of minutes return an "X hours" / "1 hour" / "X minutes" / "1 minute" text
sub hours_minutes_text {
  my $mins = shift;

  if ($mins == 1) {
    return "one minute";
  } elsif ($mins < 60) {
    return $mins . " minutes";
  } elsif ($mins < 120) {
    return "one hour";
  } else {
    return int($mins / 60) . " hours";
  }
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

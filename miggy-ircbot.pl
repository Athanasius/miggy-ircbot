#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;
use open qw{:std :utf8};

use POE;
use POE::Component::IRC::Qnet::State;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Qnet::Auth;
use POE::Component::IRC::Plugin::AutoJoin;
#use POE::Component::IRC::Plugin::Console;
use POE::Component::IRC::Plugin::Seen;
use POE::Component::IRC::Plugin::BotCommand;

use MiggyIRCBot::ConfigFile;
use MiggyIRCBot::HTTP;
use MiggyIRCBot::RSS;
use MiggyIRCBot::URLParse;
use MiggyIRCBot::AlarmClock;
use POSIX qw/strftime/;
use Data::Dumper;
#use Devel::StackTrace;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot.conf");
if (!defined($config)) {
  die "No config!";
}

my $irc = POE::Component::IRC::Qnet::State->spawn();
my $http;

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
      In_channels => 0,
      Addressed => 0,
      Prefix => '!',
      Method => 'privmsg',
      Ignore_unknown => 0,
      Eat => 1,
    )
  );

  $heap->{connector} = POE::Component::IRC::Plugin::Connector->new();
  $irc->plugin_add( 'Connector' => $heap->{connector} );

  $irc->yield ( connect => {
      Nick => $config->NickName,
      Server => $config->ServerName,
      Port => $config->ServerPort,
      Ircname => $config->IrcName
    }
  );

#  $irc->plugin_add( 'Console',
#    POE::Component::IRC::Plugin::Console->new(
#      bindport => $config->getconf('console_port'),
#      password => $config->getconf('console_password'),
#    )
#  );
  if ($config->ServerName =~ /\.quakenet\.org$/i
    and defined($config->ServerAuth->get('Type')) and $config->ServerAuth->get('Type') eq 'Q'
    and defined($config->ServerAuth->get('Name')) and defined($config->ServerAuth->get('Password'))) {
    $irc->plugin_add('Qnet::Auth',
      POE::Component::IRC::Qnet::Auth->new(
        'AuthName' => $config->ServerAuth->get('Name'),
        'Password' => $config->ServerAuth->get('Password')
      )
    );
  }
  $irc->plugin_add('AutoJoin',
    POE::Component::IRC::Plugin::AutoJoin->new(
      Channels => [ $config->Channel->get('Name') ],
      NickServ_delay => 60,
    )
  );
  $irc->plugin_add('Seen',
    POE::Component::IRC::Plugin::Seen->new(
      filename => $config->Seen->get('FileStore')
    )
  );

  $irc->plugin_add('MiggyIRCBotHTTP',
    $http = MiggyIRCBot::HTTP->new()
  );
  if (! $irc->plugin_add('MiggyIRCBotRSS',
    MiggyIRCBot::RSS->new(
      http_alias => $http->{'http_alias'},
      rss_url => $config->Rss->block('Feed')->get('Url'),
      rss_file => $config->Rss->block('Feed')->get('FileStore')
    )
  )) {
    return 0;
  }
  $kernel->delay('rss_check', $config->Rss->block('Feed')->get('CheckInterval'));

  if (! $irc->plugin_add('MiggyIRCBotURLParse',
    MiggyIRCBot::URLParse->new(
      http_alias => $http->{'http_alias'},
      youtube_api_key => $config->UrlParser->block('YouTube')->get('ApiKey'),
      imgur_clientid => $config->UrlParser->block('Imgur')->get('ClientId'),
      imgur_clientsecret => $config->UrlParser->block('Imgur')->get('ClientSecret'),
      reddit_username => $config->UrlParser->block('Reddit')->get('UserName'),
      reddit_password => $config->UrlParser->block('Reddit')->get('Password'),
      reddit_clientid => $config->UrlParser->block('Reddit')->get('ClientId'),
      reddit_secret => $config->UrlParser->block('Reddit')->get('ClientSecret'),
      twitchtv_clientid => $config->UrlParser->block('Twitch')->get('ClientId'),
    )
  )) {
    return 0;
  }

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
  $irc->yield('mode', $irc->nick_name . " +x");

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
    $irc->yield(privmsg => $channel, $config->Channel->get('ReadyMessage'));
  }
}

#irc_invite
sub irc_invite {
  my $nick = (split /!/, $_[ARG0])[0];
  my $channel = $_[ARG1];
  my $irc = $_[SENDER]->get_heap();

  printf "irc_invite - Nick: '%s', Channel: '%s'\n", $nick, $channel;
  if (lc($channel) eq lc($config->Channel->get('Name'))) {
    print " irc_invite: For our channel\n";
    my $on_channel = undef;
    foreach my $c ( keys %{$irc->channels()} ) {
      if (lc($c) eq lc($config->Channel->get('Name'))) {
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

  mylog("HANDLE_RSS_CHECK: Triggering 'get_rss_items'");
  $kernel->yield('get_rss_items', { _channel => $config->Channel->get('Name'), _reply_to => $config->Channel->get('Name'), _errors_to => $config->Channel->get('Name'), session => $session, quiet => 1 } );

  mylog("HANDLE_RSS_CHECK: Setting new run after " . $config->Rss->block('Feed')->get('CheckInterval') . " seconds");
  $kernel->delay('rss_check', $config->Rss->block('Feed')->get('CheckInterval'));
}

sub irc_botcmd_rss {
  my ($kernel, $session, $sender, $channel, $arg) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  if (defined($arg)) {
    if ($arg eq "latest") {
      $kernel->yield('get_rss_latest', { _reply_to => $nick, session => $session, quiet => 0 } );
    }
  } else {
    unless ($poco->is_channel_operator($config->Channel->get('Name'), $nick)
      or $poco->has_channel_voice($config->Channel->get('Name'), $nick)) {
      return;
    }
    $irc->yield('privmsg', $nick, "Running RSS query, please wait ...");
    $kernel->yield('get_rss_items', { _reply_to => $config->Channel->get('Name'), _errors_to => $nick, session => $session, quiet => 0 } );
  }
}

sub irc_miggybot_rss_newitems {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $reply_to = delete $args->{_reply_to};
  my $errors_to = delete $args->{_errors_to};
  my %topics;
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS:\n";

  if (defined($_[ARG1])) {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Got some item(s)\n";
    for my $i (@_[ARG1..$#_]) {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Item with permaLink '%s'\n", $i->{'permaLink'};
      # https://forums.frontier.co.uk/showthread.php?t=101801&p=3541911#post3541911
      if ($i->{'permaLink'} =~ /http(s)?:\/\/forums\.frontier\.co\.uk\/showthread\.php\?t=(?<t>[0-9]+)(&p=(?<p>[0-9]+)#post(?<post>[0-9]+))?$/
        or $i->{'permaLink'} =~ /http(s)?:\/\/forums\.frontier\.co\.uk\/showthread\.php\/(?<t>[0-9]+)-.+(\?p=(?<p>[0-9]+)#post(?<post>[0-9]+))?$/) {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Item has a Frontier Forums permaLink\n";
        my $post;
        if (defined($+{'p'})) {
          $post = $+{'p'};
        } else {
          $post = 0;
        }
        if (!defined($topics{$+{'t'}})) {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Item topic hasn't been seen yet in this set\n";
          $topics{$+{'t'}} = [ { 'guid' => $i->{'permaLink'}, 'title' => $i->{'title'}, 'post' => $post } ];
        } else {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Item topic HAS been seen already in this set\n";
          push @{$topics{$+{'t'}}}, { 'guid' => $i->{'permaLink'}, 'title' => $i->{'title'}, 'post' => $post };
        }
      }# else {
#        printf STDERR "Not a Frontier Forums URL: %s\n", $i->{'permaLink'};
#      }
    }
    foreach my $t (keys(%topics)) {
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Considering topic '%s'\n%s\n", $t, Dumper($topics{$t});
#printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Considering topic '%s'[%d]\n", $t, $#{$topics{$t}} + 1;
#print STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Stack:\n", Devel::StackTrace->new->as_string, "\n";
      @{$topics{$t}} = sort( { $a->{'post'} <=> $b->{'post'} } @{$topics{$t}} );
      my $blurb = 'New RSS item: "' . $topics{$t}->[0]->{'title'} . '" - ' . $topics{$t}->[0]->{'guid'};
      if ($#{$topics{$t}} > 1) {
        $blurb .= sprintf(" (and %d other posts)", $#{$topics{$t}});
      } elsif ($#{$topics{$t}} > 0) {
        $blurb .= " (and one other post)";
      }
      $irc->yield('privmsg', $reply_to, $blurb);
    }
  } elsif (! $args->{quiet}) {
      $irc->yield('privmsg', $errors_to, 'No new RSS items at this time');
  }
}

sub irc_miggybot_rss_latest {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $reply_to = delete $args->{_reply_to};

#printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST\n";
  $irc->yield('privmsg', $reply_to, 'The latest 10 RSS items follow...');
  for my $i (@_[ARG1..$#_]) {
#printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST: Spitting out item\n";
    $irc->yield('privmsg', $reply_to, 'RSS item: "' . $i->{'title'} . '" - ' . $i->{'guid'});
  }
  $irc->yield('privmsg', $reply_to, 'End of latest 10 RSS items.');
}

sub irc_miggybot_rss_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $reply_to = delete $args->{_reply_to};

mylog("irc_miggybot_rss_error...");
  $irc->yield('privmsg', $reply_to, "RSS Error: " . $error);
}
###########################################################################

###########################################################################
# URL Parsing
###########################################################################
sub irc_miggybot_url_success {
  my ($kernel,$sender,$args,$title) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $channel = delete $args->{_channel};

#printf STDERR "irc_miggybot_url_success:\n";
  if (defined($_[ARG1]) and $_[ARG1] ne "" and $args->{quiet} == 0) {
    my $blurb = $_[ARG1];
    $irc->yield('privmsg', $channel, $blurb);
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

  $irc->yield('privmsg', $nick, "Frontier Developments' YouTube channel is at: https://www.youtube.com/user/FrontierDevelopments");
}
# Twitch.TV
sub irc_botcmd_twitch {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $nick, "Frontier Developments' Twitch.TV channel is at: http://www.twitch.tv/frontierdev");
}
sub irc_botcmd_community_site {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $nick, "The (still beta?) Elite Dangerous Community site can be found at: https://community.elitedangerous.com/");
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
  my $channel = $config->Channel->get('Name');

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

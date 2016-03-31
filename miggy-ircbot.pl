#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;
use open qw{:std :utf8};

use POE;
use POE::Component::IRC::Qnet::State;
use POE::Component::IRC::Plugin::Connector;
use POE::Component::IRC::Qnet::Auth;
use POE::Component::IRC::Plugin::AutoJoin;
use POE::Component::IRC::Plugin::Console;
use POE::Component::IRC::Plugin::Seen;
use POE::Component::IRC::Plugin::BotCommand;

use MiggyIRCBot::Crowdfund;
use MiggyIRCBot::ConfigFile;
use MiggyIRCBot::HTTP;
use MiggyIRCBot::RSS;
use MiggyIRCBot::URLParse;
use MiggyIRCBot::AlarmClock;
use POSIX qw/strftime/;
use Data::Dumper;
#use Devel::StackTrace;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot-config.txt");
if (!defined($config)) {
  die "No config!";
}
# We don't want no proxy
if (defined($config->getconf('no_env_http_proxy')) and lc($config->getconf('no_env_http_proxy')) eq 'true') {
printf STDERR "no_env_http_proxy is 'true', nuking HTTP_PROXY and http_proxy in ENV\n";
  $ENV{'HTTP_PROXY'} = undef;
  $ENV{'http_proxy'} = undef;
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
      irc_botcmd_crowdfund irc_sc_crowdfund_success irc_sc_crowdfund_error
      irc_miggybot_url_success irc_miggybot_url_error
      irc_botcmd_rss irc_miggybot_rss_newitems irc_miggybot_rss_error irc_miggybot_rss_latest
      irc_botcmd_alarm irc_miggybot_alarm_announce
      irc_botcmd_youtube
      irc_botcmd_twitch
      irc_botcmd_hangover
      irc_botcmd_wmh
      irc_botcmd_atv
      irc_botcmd_10ftc
      irc_botcmd_commlink
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
        crowdfund => { 
          info => 'Takes no arguments, reports current crowdfund data.',
          aliases => [ 'cf' ],
        },
        rss => {
          info => 'With no argument checks RSI RSS feed (OPS/VOICE ONLY).  With "latest" as argument it will repeat the latest posted item details (anyone).',
        },
        youtube => {
          info => "Displays RSI YouTube channel URL"
        },
        twitch => {
          info => "Displays RSI Twitch.TV channel URL"
        },
        hangover => {
          info => "Displays Wingman's UStream channel URL, where he hosts his post WMH Hangover shows",
          aliases => [ 'ustream', 'wmho' ],
        },
        wmh => {
          info => "Displays info about WingMan's Hangar, what it was, where to watch archived episodes etc.",
        },
        commlink => {
          info => "Displays the URL for the RSI Comm-Link",
          aliases => [ 'comm-link', 'latest', 'news' ],
        },
        'atv' => {
          info => "Displays info for About the Verse, what it is, when it's available etc.",
        },
        '10ftc' => {
          info => "Displays info about 10 For the Chairman, what it is, when it's available etc.",
          aliases => [ 'tftc' ],
        },
      },
      In_channels => 1,
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
  if ($config->getconf('ircserver') =~ /\.quakenet\.org$/i
    and defined($config->getconf('qauth')) and defined($config->getconf('qpass'))) {
    $irc->plugin_add('Qnet::Auth',
      POE::Component::IRC::Qnet::Auth->new(
        'AuthName' => $config->getconf('qauth'),
        'Password' => $config->getconf('qpass')
      )
    );
  }
  $irc->plugin_add('AutoJoin',
    POE::Component::IRC::Plugin::AutoJoin->new(
      Channels => [ $config->getconf('channel') ],
      NickServ_delay => 60,
    )
  );
  $irc->plugin_add('Seen',
    POE::Component::IRC::Plugin::Seen->new(
      filename => $config->getconf('seen_filestore')
    )
  );

  $irc->plugin_add('MiggyIRCBotHTTP',
    $http = MiggyIRCBot::HTTP->new(
      no_http_proxy => $config->getconf('no_http_proxy')
    )
  );
  if (! $irc->plugin_add('MiggyIRCBotRSS',
    MiggyIRCBot::RSS->new(
      http_alias => $http->{'http_alias'},
      rss_url => $config->getconf('rss_url'),
      rss_file => $config->getconf('rss_filestore')
    )
  )) {
    return 0;
  }
  $kernel->delay('rss_check', $config->getconf('rss_check_time'));

  $irc->plugin_add('SCCrowdfund',
    MiggyIRCBot::Crowdfund->new(
      http_alias => $http->{'http_alias'}
    )
  );
  # Get Crowdfund::$last_cf initialised
  $kernel->yield('get_crowdfund', { _channel => $config->getconf('channel'), session => $session, crowdfund_url => $config->getconf('crowdfund_url'), autocheck => 1, quiet => 1 } );
  # And set up the delayed check
  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));

  $irc->plugin_add('SCURLParse',
    MiggyIRCBot::URLParse->new(
      http_alias => $http->{'http_alias'}
    )
  );

  if (! $irc->plugin_add('MiggyIRCBotURLParse',
    MiggyIRCBot::URLParse->new(
      http_alias => $http->{'http_alias'},
      youtube_api_key => $config->getconf('youtube_api_key'),
      imgur_clientid => $config->getconf('imgur_clientid'),
      imgur_clientsecret => $config->getconf('imgur_clientsecret'),
      reddit_username => $config->getconf('reddit_username'),
      reddit_password => $config->getconf('reddit_password'),
      reddit_clientid => $config->getconf('reddit_clientid'),
      reddit_secret => $config->getconf('reddit_secret'),
      twitchtv_clientid => $config->getconf('twitchtv_clientid'),
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
  $irc->yield('mode', $config->getconf('nickname') . " +x");

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
    $irc->yield(privmsg => $channel, $config->getconf('ready_message'));
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
# Crowdfund related functions
###########################################################################
### The in-channel checking of crowdfund
sub irc_botcmd_crowdfund {
  my ($kernel, $session, $sender, $channel) = @_[KERNEL, SESSION, SENDER, ARG1];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

#  unless ($poco->is_channel_operator($channel, $nick)
#    or $poco->has_channel_voice($channel, $nick)) {
#    return;
#  }
  $irc->yield('privmsg', $channel, "Running crowdfund query, please wait ...");
  $kernel->yield('get_crowdfund', { _channel => $channel, session => $session, crowdfund_url => $config->getconf('crowdfund_url'), autocheck => 0, quiet => 0 } );
}

### Function to check current/last crowdfund against thresholds
sub handle_crowdfund_check_threshold {
  my ($kernel, $session) = @_[KERNEL, SESSION];

  $kernel->yield('get_crowdfund', { _channel => $config->getconf('channel'), session => $session, crowdfund_url => $config->getconf('crowdfund_url'), autocheck => 1, quiet => 0 } );

  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));
}

sub irc_sc_crowdfund_success {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

#printf STDERR "irc_sc_crowdfund_success:\n";
#printf STDERR " quiet: %s\n", Dumper($args->{quiet});
#printf STDERR " ARG1: %s\n", Dumper($_[ARG1]);
  if (defined($_[ARG1]) and $args->{quiet} == 0) {
    my $crowd = $_[ARG1];
    if (defined(${$crowd}{'error'})) {
      $irc->yield('privmsg', $channel, ${$crowd}{'error'});
    } elsif (defined(${$crowd}{'report'})) {
      $irc->yield('privmsg', $channel, ${$crowd}{'report'});
    }
  }
}

sub irc_sc_crowdfund_error {
  my ($kernel, $sender, $args, $new_cf) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_sc_crowdfund_error...");
  $irc->yield('privmsg', $channel, "Crowdfund Error: " . ${$new_cf}{'error'});
}
###########################################################################

###########################################################################
# RSS Checking
###########################################################################
sub handle_rss_check {
  my ($kernel, $session) = @_[KERNEL, SESSION];

  mylog("HANDLE_RSS_CHECK: Triggering 'get_rss_items'");
  $kernel->yield('get_rss_items', { _channel => $config->getconf('channel'), _reply_to => $config->getconf('channel'), _errors_to => $config->getconf('channel'), session => $session, quiet => 1 } );

  mylog("HANDLE_RSS_CHECK: Setting new run after " . $config->getconf('rss_check_time') . " seconds");
  $kernel->delay('rss_check', $config->getconf('rss_check_time'));
}

sub irc_botcmd_rss {
  my ($kernel, $session, $sender, $channel, $arg) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  if (defined($arg)) {
    if ($arg eq "latest") {
      $kernel->yield('get_rss_latest', { _reply_to => $channel, session => $session, quiet => 0 } );
    }
  } else {
    unless ($poco->is_channel_operator($config->getconf('channel'), $nick)
      or $poco->has_channel_voice($config->getconf('channel'), $nick)) {
      return;
    }
    $irc->yield('privmsg', $config->getconf('channel'), "Running RSS query, please wait ...");
    $kernel->yield('get_rss_items', { _reply_to => $config->getconf('channel'), _errors_to => $config->getconf('channel'), session => $session, quiet => 0 } );
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
      $irc->yield('privmsg', $reply_to, 'New Comm-Link: "' . $i->{'title'} . '" - ' . $i->{'permaLink'});
    }
  } elsif (! $args->{quiet}) {
      $irc->yield('privmsg', $errors_to, 'No new Comm-links at this time');
  }
}

sub irc_miggybot_rss_latest {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $reply_to = delete $args->{_reply_to};

printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST\n";
  for my $i (@_[ARG1..$#_]) {
printf STDERR "_IRC_MiggyIRCBot_RSS_LATEST: Spitting out item\n";
    $irc->yield('privmsg', $reply_to, 'Latest RSS item: "' . $i->{'title'} . '" - ' . $i->{'guid'});
  }
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

  $irc->yield('privmsg', $channel, "Roberts Space Industries YouTube channel is at: http://www.youtube.com/user/RobertsSpaceInd");
}
# Twitch.TV
sub irc_botcmd_twitch {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "Roberts Space Industries Twitch.TV channel is at: http://www.twitch.tv/roberts_space_ind_ch_1");
}
# Hangover / Ustream
sub irc_botcmd_hangover {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "Wingman's Hangover was when WingMan streamed on ustream ~15 minutes after the end of Wingman's Hangar.  He might still pop up on there now and then: http://www.ustream.tv/channel/wingmancig");
}
# Wingman's Hangar
sub irc_botcmd_wmh {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "WingMan's Hangar was a look at CIG/SC news each week.  It aired at 11am US Central time every Wednesday, excepting some holidays and special events, and ran for a total of 72 episodes.  You can watch the archived episodes on YouTube: https://www.youtube.com/playlist?list=PLVct2QDhDrB0sipIorv4skO-XR8bAO7Pp");
}
# Around the Verse
sub irc_botcmd_atv {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "Around the Verse is a look at CIG/SC news each week.  It airs at mid-day US Pacific time every Thursday, excepting some holidays and special events.  You can watch it on the RSI YouTube channel (uploaded, not live): https://www.youtube.com/user/RobertsSpaceInd");
}
# Ten For The Chairman
sub irc_botcmd_10ftc {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "10 For the Chairman is a weekly show featuring Chris Roberts answering 10 subscribers' questions.  It airs at 3pm US Pacific time every Monday, excepting some holidays and special events.  You can watch it on the RSI YouTube channel (uploaded, not live): https://www.youtube.com/user/RobertsSpaceInd");
}

sub irc_botcmd_commlink {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "The latest news from Roberts Space Industries and Cloud Imperium Games about Star Citizen should be on: http://www.robertsspaceindustries.com/comm-link/ (NB: A few posts only go to the front page: http://www.robertsspaceindustries.com/ )");
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

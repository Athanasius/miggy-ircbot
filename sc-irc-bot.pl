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
use SCIrcBot::URLParse;
use SCIrcBot::AlarmClock;
use POSIX qw/strftime/;
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
      irc_public
      irc_ctcp_action
      irc_invite
      irc_botcmd_crowdfund irc_sc_crowdfund_success irc_sc_crowdfund_error
      irc_botcmd_rss irc_sc_rss_newitems irc_sc_rss_error irc_sc_rss_latest
      irc_sc_url_success irc_sc_url_error
      irc_botcmd_alarm irc_sc_alarm_announce
      irc_botcmd_youtube
      irc_botcmd_twitch
      irc_botcmd_hangover
      irc_botcmd_wmh
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
          info => "Displays info about WingMan's Hangar, what it is, when it is, where it is",
        },
        commlink => {
          info => "Displays the URL for the RSI Comm-Link",
          aliases => [ 'comm-link', 'latest', 'news' ],
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
  # Get Crowdfund::$last_cf initialised
  $kernel->yield('get_crowdfund', { _channel => $config->getconf('channel'), session => $session, crowdfund_url => $config->getconf('crowdfund_url'), autocheck => 1, quiet => 1 } );
  # And set up the delayed check
  $kernel->delay('crowdfund_check_threshold', $config->getconf('crowdfund_funds_check_time'));

  $irc->plugin_add('SCURLParse',
    SCIrcBot::URLParse->new()
  );

  $irc->plugin_add('SCAlarmClock',
    SCIrcBot::AlarmClock->new()
  );
  $kernel->yield('init_alarms', { session_id => $session });

  $irc->yield( register => 'all' );
}

###########################################################################
# Responding to IRC events
###########################################################################
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
  } # elsif ($msg =~ /(^|[\s,.!\?:]+)(?<hoststart>[a-zA-Z0-9\.-]+)\.(?<tld>ac|ad|ae|aero|af|ag|ai|al|am|an|ao|aq|ar|arpa|as|asia|at|au|aw|ax|az|ba|bb|bd|be|bf|bg|bh|bi|biz|bj|bl|bm|bn|bo|bq|br|bs|bt|bv|bw|by|bz|ca|cat|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|com|coop|cr|cu|cv|cw|cx|cy|cz|de|dj|dk|dm|do|dz|ec|edu|ee|eg|eh|er|es|et|eu|fi|fj|fk|fm|fo|fr|ga|gb|gd|ge|gf|gg|gh|gi|gl|gm|gn|gov|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|info|int|io|iq|ir|is|it|je|jm|jo|jobs|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|me|mf|mg|mh|mil|mk|ml|mm|mn|mo|mobi|mp|mq|mr|ms|mt|mu|museum|mv|mw|mx|my|mz|na|name|nc|ne|net|nf|ng|ni|nl|no|np|nr|nu|nz|om|org|pa|pe|pf|pg|ph|pk|pl|pm|pn|post|pr|pro|ps|pt|pw|py|qa|re|ro|rs|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|sk|sl|sm|sn|so|sr|ss|st|su|sv|sx|sy|sz|tc|td|tel|tf|tg|th|tj|tk|tl|tm|tn|to|tp|tr|travel|tt|tv|tw|tz|ua|ug|uk|um|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|xxx|ye|yt|za|zm|zw)([\s,.!\?:]+|$)/) {
  #  $url = 'http://' . $+{'hoststart'} . "." . $+{'tld'};
  #}
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

sub irc_sc_rss_latest {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $channel = delete $args->{_channel};

printf STDERR "_IRC_SC_RSS_LATEST\n";
  for my $i (@_[ARG1..$#_]) {
#printf STDERR "_IRC_SC_RSS_LATEST: Spitting out item\n";
    $irc->yield('privmsg', $channel, 'Latest RSI Comm-Link: "' . $i->{'title'} . '" - ' . $i->{'guid'});
  }
}

sub irc_sc_rss_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_sc_rss_error...");
  $irc->yield('privmsg', $channel, "RSS Error: " . $error);
}
###########################################################################

###########################################################################
# URL Parsing
###########################################################################
sub irc_sc_url_success {
  my ($kernel,$sender,$args,$title) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $channel = delete $args->{_channel};

#printf STDERR "irc_sc_url_success:\n";
  if (defined($_[ARG1]) and $args->{quiet} == 0) {
    my $title = $_[ARG1];
    $irc->yield('privmsg', $channel, "URL Title: " . $title);
  }
}

sub irc_sc_url_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $channel = delete $args->{_channel};

mylog("irc_sc_url_error...");
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

  $irc->yield('privmsg', $channel, "Wingman's Hangover often happens ~15 minutes after the end of Wingman's Hangar and is available on Wingman's USTREAM channel: http://www.ustream.tv/channel/wingmancig");
}
sub irc_botcmd_wmh {
  my ($kernel, $session, $sender, $channel, $url) = @_[KERNEL, SESSION, SENDER, ARG1, ARG2];
  my $nick = (split /!/, $_[ARG0])[0];
  my $poco = $sender->get_heap();

  $irc->yield('privmsg', $channel, "WingMan's Hangar is a look at CIG/SC news each week.  It airs at 11am US Central time every Friday, excepting some holidays and special events.  You can watch it on the RSI Twitch.TV channel: http://www.twitch.tv/roberts_space_ind_ch_1");
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

sub irc_sc_alarm_announce {
  my ($kernel, $sender, $alarmtag, $alarm, $pre) = @_[KERNEL, SENDER, ARG0, ARG1, ARG2];
  my $channel = $config->getconf('channel');

  #printf STDERR "irc_sc_alarm_announce: alarm = %s\n", Dumper($alarm);
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

#!/usr/bin/perl -w -Ishare/perl/5.14.2 -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use strict;
use POE;
use POE::Component::IRC;
use MiggyIRCBot::ConfigFile;
use MiggyIRCBot::HTTP;
use MiggyIRCBot::RSS;
use POSIX qw/strftime/;
use Data::Dumper;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot.conf");
if (!defined($config)) {
  die "No config!";
}

my $irc = POE::Component::IRC->spawn();
my $http;

POE::Session->create(
  package_states => [
    main => [ qw( _default _start irc_001
      irc_miggybot_rss_newitems irc_miggybot_rss_error
      ) ]
  ],
  inline_states => {
    rss_check => \&handle_rss_check
  }
);

$poe_kernel->run();

sub _start {
  my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

  $irc->plugin_add('MiggyIRCBotHTTP',
    $http = MiggyIRCBot::HTTP->new(
    )
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

  $kernel->yield('rss_check', { _channel => "#test", session => $session, quiet => 0, url => $ARGV[0] } );
}

sub irc_001 {
  my ($kernel, $sender) = @_[KERNEL, SENDER];
  my $irc = $_[SENDER]->get_heap();

  print " irc_001:\n";

  # Set mode +x
  print " Attempt to set usermode +x\n";
  $irc->yield('mode', $config->NickName . " +x");

  return;
}

###########################################################################
# RSS
###########################################################################
sub handle_rss_check {
  my ($kernel, $session) = @_[KERNEL, SESSION];

  mylog("HANDLE_RSS_CHECK: Triggering 'get_rss_items'");
  $kernel->yield('get_rss_items', { _channel => $config->Channel->get('Name'), _reply_to => $config->Channel->get('Name'), _errors_to => $config->Channel->get('Name'), session => $session, quiet => 0 } );

  mylog("HANDLE_RSS_CHECK: Setting new run after " . $config->Rss->block('Feed')->get('CheckInterval') . " seconds");
  $kernel->delay('rss_check', $config->Rss->block('Feed')->get('CheckInterval'));
}

sub irc_miggybot_rss_newitems {
  my ($kernel,$sender,$args) = @_[KERNEL,SENDER,ARG0];
  my $reply_to = delete $args->{_reply_to};
  my $errors_to = delete $args->{_errors_to};
  my %topics;
printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS:\n";

  if (defined($_[ARG1])) {
printf STDERR "IRC_MIGGYBOT_RSS_NEWITEMS: Got some item(s)\n";
    for my $i (@_[ARG1..$#_]) {
      print 'New Comm-Link: "' . $i->{'title'} . '" - ' . $i->{'permaLink'}, "\n";
    }
  } elsif (! $args->{quiet}) {
      print 'No new Comm-links at this time', "\n";
  }
  print "IRC_MIGGYBOT_RSS_NEWITEMS: Done, shutting down\n";
  $irc->plugin_del('MiggyIRCBotRSS');
  $irc->plugin_del('MiggyIRCBotHTTP');
  $irc->shutdown();
  $kernel->stop();
}

sub irc_miggybot_rss_error {
  my ($kernel, $sender, $args, $error) = @_[KERNEL, SENDER, ARG0, ARG1];
  my $reply_to = delete $args->{_reply_to};

  mylog("irc_miggybot_rss_error... '", $error, "'");
  if (defined($error) and $error ne "") {
    print "RSS Error: " . $error;
  }
  $irc->plugin_del('MiggyIRCBotRSS');
  $irc->plugin_del('MiggyIRCBotHTTP');
  $irc->shutdown();
  $kernel->stop();
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

package SCIrcBot::AlarmClock;

use strict;
use warnings;
use POE;
use POE::Component::IRC::Plugin qw(:ALL);
use POSIX qw/strftime mktime/;
use Date::Language;
use Date::Parse;

use Data::Dumper;

use constant { SEC => 0, MIN => 1, HOUR => 2, MDAY => 3, MON => 4, YEAR => 5, WDAY => 6, YDAY => 7, ISDST => 8, };

my %alarms = (
  'wmh' => {
    'fullname' => "Wingman's Hangar Reminder",
    'announce_text' => "Wingman's hangar is starting now! http://twitch.tv/roberts_space_ind_ch_1",
    'time' => 'Tue 16:27:15',
    'timezone' => 'CST6CDT',
    'pre_announce_times' => [60, 30, 15, 5], # Minutes
    'pre_announce_text' => "Wingman's Hangar starts in %d minutes: http://twitch.tv/roberts_space_ind_ch_1",
  },
  '1yrstream' => {
    'fullname' => "1 Year Anniversay Stream",
    'announce_text' => "1 year anniversay stream should be starting now! http://twitch.tv/roberts_space_ind_ch_1",
    'time' => 'Thu Oct 10 2013 18:30:00',
    'timezone' => 'CST6CDT',
    'pre_announce_times' => [60, 30, 15, 5], # Minutes
    'pre_announce_text' => "Wingman's Hangar starts in %d minutes: http://twitch.tv/roberts_space_ind_ch_1",
  },
);

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

	return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );
  $self->{session_id} = POE::Session->create(
    object_states => [
      $self => [ qw(_shutdown _start alarm_announce) ],
    ],
  )->ID();
  $poe_kernel->state( 'init_alarms', $self );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->state( 'init_alarms' );
  $poe_kernel->call( $self->{session_id} => '_shutdown' );
  delete $self->{irc};
  return 1;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{session_id} = $_[SESSION]->ID();
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );

  undef;
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->alarm_remove_all();
  $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
  undef;
}

# Initialise alarm system, has to be this, not _start so that we can
# pass in the IRC session in order to be able to send it events
sub init_alarms {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;

  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  foreach my $a (keys(%alarms)) {
    my $t = parse_alarm_time(${$alarms{$a}}{'time'}, ${$alarms{$a}}{'timezone'});
    print strftime("%Y-%m-%d %H:%M:%S %Z\n", gmtime($t));
    if ($t > 0) {
    # Now set a delay for the specified time to callback
      printf (STDERR "kernel->alarm('alarm_announce', %d, %s\n", $t, $a);
      $kernel->alarm('alarm_announce', $t, \%args, $a);
    } else {
      printf STDERR "Time has already passed\n";
    }
  }
#exit(0);

  undef;
}

sub alarm_announce {
  my ($kernel, $self, $args, $alarm) = @_[KERNEL, OBJECT, ARG0, ARG1];

  printf STDERR "alarm_announce for '%s'\n", $alarm;

  $kernel->post($args->{session_id}, 'irc_sc_alarm_announce', $a, $alarms{$a});

  undef;
}

###########################################################################
# Parse a time string and return a Unix Epoch timestamp on when it will
# next occur.
###########################################################################
sub parse_alarm_time {
  my ($timestr, $timezone) = @_;
  printf STDERR "parse_alarm_time('%s', '%s'):\n", $timestr, $timezone;
  my $time = 0;
  my $old_tz = $ENV{'TZ'};
  $ENV{'TZ'} = $timezone;

  if ($timestr =~ /^\w{3}\s\w{3}\s{1,2}\d{1,2}\s\d{4}\s\d{2}:\d{2}:\d{2}$/) {
  # A specific date and time 'Thu Oct 10 18:30:00'
    my $lang = Date::Language->new('English');
    $time = $lang->str2time($timestr);
    if ($time < time()) {
      $time = 0; # Time has passed, so return epoch
    }
  } elsif ($timestr =~ /^(?<dayofweek>\w{3})\s(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})$/) {
    # A weekly repeat, i.e. 'Fri 11:00:00',
    my ($dayofweek, $hour, $minute, $second) = ($+{'dayofweek'}, $+{'hour'}, $+{'minute'}, $+{'second'});
    #printf STDERR "parse_alarm_time: dow = %s, hour = %s, min = %s, sec = %s\n", $dayofweek, $hour, $minute, $second;
    # Get current time struct: ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
    my @now = localtime(time());
    # Check day of week against the string
    # tm_wday   The number of days since Sunday, in the range 0 to 6.
    my @days = ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun');
    my @today = grep { $days[$_] eq $dayofweek } 0..$#days;
    #foreach my $t (@today) { print "parse_alarm_time: today = ", $t, "\n"; }
    if ($now[WDAY] < $today[0]) {
    # Today is before the weekly day we need, so set up struct_tm with the event's time and day
      $now[WDAY] = $today[0];
      $now[HOUR] = $hour; $now[MIN] = $minute; $now[SEC] = $second;
    } elsif ($now[WDAY] == $today[0]) {
      #printf STDERR "Alarm is today\n";
    # The alarm is today, but has the time passed?
    # 17:30 vs 18:00 onwards
    #       vs 17:29 or before in 17:XX, but not 16:29 or before in 16:XX
      if ($now[HOUR] > $hour
        or $now[HOUR] == $hour and $now[MIN] > $minute
        or $now[HOUR] == $hour and $now[MIN] == $minute and $now[SEC] > $second) {
        #printf STDERR "Today, but time has passed\n";
        $now[MDAY] += 7; 
        $now[WDAY] = -1;
      }
      $now[HOUR] = $hour; $now[MIN] = $minute; $now[SEC] = $second;
    } else {
    # Alarm is before today's day of the week
      $now[MDAY] += $today[0] + 7 - $now[WDAY];
      $now[WDAY] = -1;
      $now[HOUR] = $hour; $now[MIN] = $minute; $now[SEC] = $second;
    }
    $time = mktime(@now);
  }

  $ENV{'TZ'} = $old_tz;
  return $time;
}
###########################################################################

1;

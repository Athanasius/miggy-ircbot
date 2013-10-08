package SCIrcBot::AlarmClock;

use strict;
use warnings;
use POE;
use POE::Component::IRC::Plugin qw(:ALL);
use POSIX qw/strftime mktime/;
use Date::Language;
use Date::Parse;

my %alarms = (
  'wmh' => (
    'fullname' => "Wingman's Hangar Reminder",
    'announce_text' => "Wingman's hangar is starting now! http://twitch.tv/roberts_space_ind_ch_1",
    'time' => 'Fri 11:00:00',
    'timezone' => 'CST6CDT',
    'pre_announce_times' => [60, 30, 15, 5], # Minutes
    'pre_announce_text' => "Wingman's Hangar starts in %d minutes: http://twitch.tv/roberts_space_ind_ch_1",
  ),
  '1yrstream' => (
    'fullname' => "1 Year Anniversay Stream",
    'announce_text' => "1 year anniversay stream should be starting now! http://twitch.tv/roberts_space_ind_ch_1",
    'time' => 'Thu Oct 10 18:30:00',
    'timezone' => 'CST6CDT',
    'pre_announce_times' => [60, 30, 15, 5], # Minutes
    'pre_announce_text' => "Wingman's Hangar starts in %d minutes: http://twitch.tv/roberts_space_ind_ch_1",
  ),
);

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

  foreach my $a (keys(%alarms)) {
    my $t = parse_alarm_time($alarms{$a}{'time'}, $alarms{$a}{'timezone'});
print strftime("%Y-%m-%d %H:%M:%S %Z\n", gmtime($t));
  }
	return $self;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{session_id} = $_[SESSION]->ID();
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
  undef;
}

###########################################################################
# Parse a time string and return a Unix Epoch timestamp on when it will
# next occur.
###########################################################################
sub parse_alarm_time {
  my ($timestr, $timezone) = @_;
  my $time = 0;
  my $old_tz = $ENV{'TZ'};
  $ENV{'TZ'} = $timezone;

  # 'Thu Oct 10 18:30:00'
  if ($timestr =~ /^\w{3}\s\w{3}\s{1,2}\d{1,2}\s\d{2}:\d{2}:\d{2}$/) {
    my $lang = Date::Language->new('English');
    my $time = $lang->str2time($timestr);
  } elsif ($timestr =~ /^(?<dayofweek>\w{3})\s(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2})$/) {
    my ($dayofweek, $hour, $minute, $second) = ($+{'dayofweek'}, $+{'hour'}, $+{'minute'}, $+{'second'});
    # 'Fri 11:00:00',
    # Get current time struct: ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
    my @now = gmtime(time());
    # Check day of week against the string
    # tm_wday   The number of days since Sunday, in the range 0 to 6.
    my @days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    my @today = grep { $days[$_] eq $dayofweek } 0..$#days;
    if ($now[6] < $today[0]) {
    # Today is before the weekly day we need, so set up struct_tm with the event's time and day
      $now[6] = $today[0];
      $now[2] = $hour;
      $now[1] = $minute;
      $now[0] = $second;
      $time = mktime(@now);
    }
  }
  $ENV{'TZ'} = $old_tz;

  return $time;
}
###########################################################################

1;

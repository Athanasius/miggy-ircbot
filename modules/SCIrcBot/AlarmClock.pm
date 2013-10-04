package SCIrcBot::AlarmClock;

use strict;
use warnings;
use POE;
use POE::Component::IRC::Plugin qw(:ALL);
use POSIX;

my %alarms = {
  'wmh' => {
    'fullname' => "Wingman's Hangar Reminder",
    'day_of_week' => 'Fri',
    'time' => '11:00:00',
    'pre_announce_time' => '15', # Minutes
    'pre_announce_text' => "Wingman's Hangar starts in 15 minutes: http://twitch.tv/roberts_space_ind_ch_1",
    'timezone' => 'CST6CDT'
  },
{;

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

	return $self;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{session_id} = $_[SESSION]->ID();
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
  undef;
}

1;

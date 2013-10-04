package SCIrcBot::AlarmClock;

use strict;
use warnings;
use POE;
use POE::Component::IRC::Plugin qw(:ALL);
use POSIX;

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

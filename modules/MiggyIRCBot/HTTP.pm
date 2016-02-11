package MiggyIRCBot::HTTP;

use strict;
use warnings;

use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);

my $no_http_proxy;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;

  if ($args{'no_http_proxy'}) {
    $no_http_proxy = $args{'no_http_proxy'};
  } else {
    $no_http_proxy = '';
  }

  return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );

printf STDERR "MiggyIRCBot::HTTP->PCI_register()\n";
  unless ( $self->{http_alias} ) {
    $self->{http_alias} = join('-', 'ua-miggyircbot', $irc->session_id() );
    $self->{follow_redirects} ||= 2;
    POE::Component::Client::HTTP->spawn(
      Alias           => $self->{http_alias},
      Agent           => 'perl:MiggyIRCBOT:v0.01 (by /u/suisanahta)',
      #Agent           => 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/48.0.2564.82 Safari/537.36',
      Timeout         => 30,
      FollowRedirects => $self->{follow_redirects},
      NoProxy         => $no_http_proxy,
    );
  }

  $self->{session_id} = POE::Session->create(
  object_states => [
    $self => [ qw(_shutdown _start ) ],
  ],
  )->ID();

printf STDERR "MiggyIRCBot::HTTP->PCI_register() - Done\n";
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->call( $self->{session_id} => '_shutdown' );
  delete $self->{irc};
  return 1;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
printf STDERR "MiggyIRCBot::HTTP->_start()\n";
  $self->{session_id} = $_[SESSION]->ID();
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
  undef;
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $kernel->alarm_remove_all();
  $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
  $kernel->call( $self->{http_alias} => 'shutdown' );
  undef;
}

1;

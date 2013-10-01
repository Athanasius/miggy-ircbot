package SCIrcBot::RSS;

use strict;
use warnings;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use XML::RSS;
use HTTP::Request;
use DBD::SQLite;

our %rss_items;
our $rss_url;
our $rss_file;
our $rss_db;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $rss_url = $args{'rss_url'};
  $rss_file = $args{'rss_file'};

  $rss_db = DBI->connect("dbi:SQLite:dbname=$rss_file","","");

  return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );
  unless ( $self->{http_alias} ) {
  $self->{http_alias} = join('-', 'ua-rss-headlines', $irc->session_id() );
  $self->{follow_redirects} ||= 2;
  POE::Component::Client::HTTP->spawn(
     Alias           => $self->{http_alias},
     Timeout         => 30,
     FollowRedirects => $self->{follow_redirects},
  );
  }
  $self->{session_id} = POE::Session->create(
  object_states => [
     $self => [ qw(_shutdown _start _get_items _parse_items) ],
  ],
  )->ID();
  $poe_kernel->state( 'get_items', $self );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->state( 'get_items' );
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
  $kernel->call( $self->{http_alias} => 'shutdown' );
  undef;
}

###########################################################################
# Code to handle getting RSS items and storing them in local hash, which
# is also tied to a database file.
#
# get_items(): User-command trigger for testing
# _get_items(): Actually retrieve current items
# _parse_items(): Triggered when we receive items back.  Check which ones
#                 are new and fire them at irc_sc_rss_newitems
###########################################################################
sub get_items {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
printf STDERR "GET_ITEMS\n";
  $kernel->post( $self->{session_id}, '_get_items', @_[ARG0..$#_] );
  undef;
}

sub _get_items {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
printf STDERR "_GET_ITEMS\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;
printf STDERR "_GET_ITEMS: posting to http_alias\n";
  $kernel->post( $self->{http_alias}, 'request', '_parse_items', HTTP::Request->new( GET => $rss_url ), \%args );
  undef;
}

sub _parse_items {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;
printf STDERR "_PARSE_ITEMS\n";
  push @params, $args->{session};
  my $result = $response->[0];
  if ( $result->is_success ) {
    my $str = $result->content;
    my $rss = XML::RSS->new();
    eval { $rss->parse($str); };
    if ($@) {
      push @params, 'irc_sc_rss_error', $args, $@;
    } else {
      push @params, 'irc_sc_rss_newitems', $args;
      foreach my $item (@{$rss->{'items'}}) {
        print "title: $item->{'title'}\n";
        print "link: $item->{'link'}\n";
        if (!defined($rss_items{$item->{'permaLink'}})) {
          print " IS NEW!\n";
          $rss_items{$item->{'permaLink'}} = $item;
          push @params, $item;
        }
      }
    }
  } else {
    push @params, 'irc_sc_rss_error', $args, $result->status_line;
  }
  $kernel->post( @params );
  undef;
}
###########################################################################

1;

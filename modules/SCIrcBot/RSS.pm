package SCIrcBot::RSS;

use strict;
use warnings;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use XML::RSS;
use HTTP::Request;

my %rss_items;
my $rss_url;
my $rss_file;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $rss_url = $args{'rss_url'};
  $rss_file = $args{'rss_file'};

printf STDERR "RSS->new\n";
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
# _get_items(): Literally just trigger retrieval of current items
# _parse_items(): Literally just stuff these into the hash/DB, marking any
#                new ones (since last report, not last check).
# report_new_items(): Report new items to channel, and mark them now as not-new
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
printf STDERR "PARSE_ITEMS\n";
  push @params, $args->{session};
  my $result = $response->[0];
  if ( $result->is_success ) {
    my $str = $result->content;
    my $rss = XML::RSS->new();
    eval { $rss->parse($str); };
    if ($@) {
      push @params, 'irc_sc_rss_error', $args, $@;
    } else {
      foreach my $item (@{$rss->{'items'}}) {
        print "title: $item->{'title'}\n";
        print "link: $item->{'link'}\n";
        foreach my $f (keys(%{$item})) {
          print " key: $f => $item->{$f} \n";
        }
      }
      #push @params, 'irc_sc_rss_items', $args;
      #push @params, $_->{'title'} for @{ $rss->{'items'} };
    }
  } else {
    push @params, 'irc_sc_rss_error', $args, $result->status_line;
  }
  $kernel->post( @params );
  undef;
}
###########################################################################

sub get_headlines {
  my ($kernel, $self, $session, $args) = @_[KERNEL, OBJECT, SESSION, ARG0];

printf STDERR "get_headlines...\n";
  $kernel->yield('get_headline', $args);
  undef;
}

sub get_headline {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
printf STDERR "get_headline...\n";
  $kernel->post( $self->{session_id}, '_get_headline', @_[ARG0..$#_] );
  undef;
}

sub _get_headline {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
printf STDERR "_GET_HEADLINE\n";
  my %args;
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;
  $kernel->post( $self->{http_alias}, 'request', '_response', HTTP::Request->new( GET => $rss_url ), \%args );
  undef;
}

sub _response {
  my ($kernel,$self,$request,$response) = @_[KERNEL,OBJECT,ARG0,ARG1];
  my $args = $request->[1];
  my @params;
#printf STDERR "_RESPONSE\n";
  push @params, $args->{session}; #, '__send_event';
  my $result = $response->[0];
  if ( $result->is_success ) {
      my $str = $result->content;
      my $rss = XML::RSS->new();
      eval { $rss->parse($str); };
      if ($@) {
  push @params, 'irc_rssheadlines_error', $args, $@;
      } else {
  push @params, 'irc_rssheadlines_items', $args;
  push @params, $_->{'title'} for @{ $rss->{'items'} };
      }
  } else {
  push @params, 'irc_rssheadlines_error', $args, $result->status_line;
  }
  $kernel->post( @params );
  undef;
}

1;

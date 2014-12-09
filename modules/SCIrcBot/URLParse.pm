package SCIrcBot::URLParse;

use strict;
use warnings;
use POSIX;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use HTTP::Request;
use HTML::TreeBuilder;

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

	return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );
  unless ( $self->{http_alias} ) {   
    $self->{http_alias} = join('-', 'ua-scircbot', $irc->session_id() );
    $self->{follow_redirects} ||= 2;
    POE::Component::Client::HTTP->spawn(
      Alias           => $self->{http_alias},
      Agent           => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
      Timeout         => 300,
      FollowRedirects => $self->{follow_redirects},
    );
  }
  $self->{session_id} = POE::Session->create(
    object_states => [
      $self => [ qw(_shutdown _start _get_url _parse_url ) ],
    ],
  )->ID();
  $poe_kernel->state( 'get_url', $self );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->state( 'get_url' );
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

sub get_url {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
#printf STDERR "GET_URL\n";
  $kernel->post( $self->{session_id}, '_get_url', @_[ARG0..$#_] );
  undef;
}

sub _get_url {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
#printf STDERR "_GET_URL\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  my $req = HTTP::Request->new('GET', $args{'url'});
#printf STDERR "_GET_URL: posting to http_alias\n";
  $kernel->post( $self->{http_alias}, 'request', '_parse_url', $req, \%args );
  undef;
}

sub _parse_url {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "_PARSE_URL\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
#printf STDERR "_PARSE_URL: res != success: $res->status_line\n";
#printf STDERR "_PARSE_URL: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_sc_url_error', $args, $error;
  } else {
#printf STDERR "_PARSE_URL: res == success\n";
    if ($res->header('Content-Type') =~ /^text\/(ht|x)ml/) {
      my $tree = HTML::TreeBuilder->new;
      $tree->parse($res->decoded_content);
      $tree->eof();
      my $title = $tree->look_down('_tag', 'title');
      if ($title) {
        push @params, 'irc_sc_url_success', $args, $title->as_text;
      } else {
        push @params, 'irc_sc_url_error', $args, "No <title> found in URL content";
      }
    } else {
      $args->{'quiet'} = 1;
      push @params, 'irc_sc_url_success', $args, "That was not an HTML page";
    }
  }

#for my $p (@params) { printf STDERR " param = $p\n"; }
  $kernel->post(@params);
  undef;
}

1;

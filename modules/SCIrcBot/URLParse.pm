package SCIrcBot::URLParse;

use strict;
use warnings;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use HTTP::Request;
use POSIX;

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
      Timeout         => 30,
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
#printf STDERR "GET_CROWDFUND\n";
  $kernel->post( $self->{session_id}, '_get_url', @_[ARG0..$#_] );
  undef;
}

sub _get_url {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
#printf STDERR "_GET_CROWDFUND\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  my $url = 'https://robertsspaceindustries.com/api/stats/getCrowdfundStats';
  my $crowd = undef;
  my $json = encode_json(
    {
      'fans' => 'true',
      'funds' => 'true',
      'alpha_slots' => 'true'
    }
  );
  my $req = HTTP::Request->new('POST', $url);
  $req->header('Content-Type' => 'application/json');
  $req->content($json);
#printf STDERR "_GET_CROWDFUND: posting to http_alias\n";
  $kernel->post( $self->{http_alias}, 'request', '_parse_url', $req, \%args );
  undef;
}

sub _parse_url {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "_PARSE_CROWDFUND\n";
  push @params, $args->{session};
  my $res = $response->[0];

  my $new_cf = ();
  if (! $res->is_success) {
#printf STDERR "_PARSE_CROWDFUND: res != success: $res->status_line\n";
    ${$new_cf}{'error'} =  "Failed to retrieve crowdfund info: " . $res->status_line;
    push @params, 'irc_sc_url_error', $args, $new_cf;
  } else {
#printf STDERR "_PARSE_CROWDFUND: res == success\n";
    push @params, 'irc_sc_url_success', $args;
    my $json = decode_json($res->content);
#printf STDERR "_PARSE_CROWDFUND: got json\n";
    $new_cf = ${$json}{'data'};
    ${$new_cf}{'time'} = time();
#printf STDERR "_PARSE_CROWDFUND: got new_cf\n";

#for my $n (keys(%{$new_cf})) { printf STDERR " new_cf{$n} = ${$new_cf}{$n}\n"; }
#for my $n (keys(%{$last_cf})) { printf STDERR " last_cf{$n} = ${$last_cf}{$n}\n"; }
printf STDERR "%s - Checking %d against %d\n", strftime("%Y-%m-%d %H:%M:%S", gmtime()), ${$last_cf}{'funds'} / 100.0, ${$new_cf}{'funds'} / 100.0;
    # Funds passed a threshold ?
    my $funds_t = next_funds_threshold(${$last_cf}{'funds'});
    if (${$new_cf}{'funds'} > $funds_t) {
      ${$new_cf}{'report'} = sprintf("Crowdfund just passed \$%s: %s", get_current_cf($new_cf));
    } else {
      ${$new_cf}{'report'} = get_current_cf($new_cf);
    }
    push @params, $new_cf;
    $last_cf = $new_cf;
  }

#for my $p (@params) { printf STDERR " param = $p\n"; }
  $kernel->post(@params);
  undef;
}

1;

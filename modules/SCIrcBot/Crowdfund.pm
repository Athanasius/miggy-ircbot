package SCIrcBot::Crowdfund;

use strict;
use warnings;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use HTTP::Request;
use JSON;
use POSIX;
use Data::Dumper;

my $last_cf = { 'funds' => 0 };

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
      $self => [ qw(_shutdown _start _get_crowdfund _parse_crowdfund ) ],
    ],
  )->ID();
  $poe_kernel->state( 'get_crowdfund', $self );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->state( 'get_crowdfund' );
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

sub get_crowdfund {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
#printf STDERR "GET_CROWDFUND\n";
  $kernel->post( $self->{session_id}, '_get_crowdfund', @_[ARG0..$#_] );
  undef;
}

sub _get_crowdfund {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
#printf STDERR "_GET_CROWDFUND\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  my $crowd = undef;
  my $json = encode_json(
    {
      'fans' => 'true',
      'funds' => 'true',
      'alpha_slots' => 'true'
    }
  );
#foreach my $a (keys(%args)) { printf STDERR "arg{%s} = %s\n", $a, $args{$a}; }
  my $req = HTTP::Request->new('POST', $args{crowdfund_url});
  $req->header('Content-Type' => 'application/json');
  $req->content($json);
#printf STDERR "_GET_CROWDFUND: posting to http_alias\n";
  $kernel->post( $self->{http_alias}, 'request', '_parse_crowdfund', $req, \%args );
  undef;
}

sub _parse_crowdfund {
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
    push @params, 'irc_sc_crowdfund_error', $args, $new_cf;
  } elsif ($res->content !~ /^{".*}$/) {
    printf STDERR "_PARSE_CROWDFUND: Not in JSON Format: '%s'\n", $res->content;
    ${$new_cf}{'error'} =  "Crowdfund info not in JSON format";
    push @params, 'irc_sc_crowdfund_error', $args, $new_cf;
  } else {
#printf STDERR "_PARSE_CROWDFUND: res == success\n";
    my $json = decode_json($res->content);
#printf STDERR "_PARSE_CROWDFUND: got json\n";
    $new_cf = ${$json}{'data'};
    ${$new_cf}{'time'} = time();
#   printf STDERR "_PARSE_CROWDFUND: got new_cf\n";

#   for my $n (keys(%{$new_cf})) { printf STDERR " new_cf{$n} = ${$new_cf}{$n}\n"; }
#   for my $n (keys(%{$last_cf})) { printf STDERR " last_cf{$n} = ${$last_cf}{$n}\n"; }
    printf STDERR "%s - Checking %d against %d\n", strftime("%Y-%m-%d %H:%M:%S", gmtime()), ${$last_cf}{'funds'} / 100.0, ${$new_cf}{'funds'} / 100.0;
    # Funds passed a threshold ?
    my $funds_t = next_funds_threshold(${$last_cf}{'funds'});
    if (${$last_cf}{'funds'} > 0 and $args->{quiet} == 0 and ${$new_cf}{'funds'} > $funds_t) {
      printf STDERR "Crowdfund has passed \$%s: %s\n", prettyprint(int($funds_t) / 100), get_current_cf($new_cf);
      ${$new_cf}{'report'} = sprintf("Crowdfund has passed \$%s: %s", prettyprint(int(previous_funds_threshold(${$new_cf}{'funds'})) / 100), get_current_cf($new_cf));
    } elsif ($args->{autocheck} != 1) {
      ${$new_cf}{'report'} = get_current_cf($new_cf);
    }
    push @params, 'irc_sc_crowdfund_success', $args, $new_cf;
#for my $p (@params) { printf STDERR " param = $p\n"; }
    $last_cf = $new_cf;
  }

  $kernel->post(@params);
  undef;
}

# Select a next threshold to test, given a current value
sub next_funds_threshold {
  # NB: this amount is in cents, not dollars
  my $current = shift;

#printf STDERR "next_funds_threshold(%d)\n", $current;
  # We'll report at every $100,000 step
  my $t = int($current / 10000000) * 10000000 + 10000000;
#$t = int($current / (5 * 100)) * (5 * 100) + (5 * 100);
#printf STDERR "next_funds_threshold(%d), proposing %d\n", $current, $t;
  # Except is that's a round million then we want finer reporting,
  # i.e. report at $X,800,000 / $X,900,000 / $X,950,000 / $X,975,000 /
  #                $X,990,000 / $X,995,000 / $X,99[6-9],000
  if ($t == int($current / 100000000) * 100000000 + 100000000) {
    # The next $100k is the next $1m as well, so drop back $50k
    $t = $t - 5000000;
#printf STDERR "\tProposing: %d\n", $t;
    if ($t < $current) {
    # This is less than current, so bump to $75k
      $t += 2500000;
#printf STDERR "\tProposing: %d\n", $t;
      if ($t < $current) {
      # This is less than current, so bump to $90k
        $t += 1500000;
#printf STDERR "\tProposing: %d\n", $t;
        if ($t < $current) {
        # This is less than current, so bump to $95k
          $t += 500000;
#printf STDERR "\tProposing: %d\n", $t;
          if ($t < $current) {
          # This iless than current, so bump by $1k increments
            while ($t < $current) {
              $t += 100000;
#printf STDERR "\tProposing: %d\n", $t;
            }
          }
        }
      }
    }
  }

printf STDERR "next_funds_threshold(%d), proposing %d\n", $current, $t;
  return $t;
}

# Select the previous threshold that we most recently passed
sub previous_funds_threshold {
  # NB: this amount is in cents, not dollars
  my $current = shift;

  # We'll report at every $100,000 step
  # Except is that's a round million then we want finer reporting,
  # i.e. report at $X,800,000 / $X,900,000 / $X,950,000 / $X,975,000 /
  #                $X,990,000 / $X,995,000 / $X,99[6-9],000
  # Thus for this we start at the current million, add 999000, then work
  # backwards.
  my $t = int($current / 100000000) * 100000000 + 99900000;
#printf STDERR "previous_funds_threshold(%d), proposing %d\n", $current, $t;
  my @steps = (50, 25, 15, 5, 1, 1, 1, 1);
  while (@steps and $current < $t) {
    $t -= 100000 * pop @steps;
#printf STDERR "\tProposing: %d\n", $t;
  }
  while ($current < $t) {
    $t -= 10000000; # Drop another 100k
#printf STDERR "\tProposing: %d\n", $t;
  }
printf STDERR "previous_funds_threshold(%d), proposing %d\n", $current, $t;

  return $t;
}
###########################################################################

sub get_current_cf {
  my $crowd = shift;

  if (defined($crowd) and defined(${$crowd}{'funds'})) {
    return sprintf("Crowdfund Total: \$%s / Fans: %s / Alpha Slots Left: %s",
      prettyprint(${$crowd}{'funds'} / 100.0),
      prettyprint(${$crowd}{'fans'}),
      prettyprint(${$crowd}{'alpha_slots_left'})
    );
  } elsif (defined($crowd) && defined(${$crowd}{'error'})) {
    return ${$crowd}{'error'};
  } else {
    return "Failed to get crowdfund data, unknown error!";
  }
}

sub prettyprint {
  my $number = sprintf "%.0f", shift @_;
  # Add one comma each time through the do-nothing loop
  1 while $number =~ s/^(-?\d+)(\d\d\d)/$1,$2/;
  # Put the dollar sign in the right place
  #$number =~ s/^(-?)/$1\$/;
  $number;
}

1;

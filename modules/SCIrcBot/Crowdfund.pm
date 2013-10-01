package SCIrcBot::Crowdfund;

use LWP;
use JSON;
use POSIX;

my $last_cf = undef;

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

  # Initialise last known value of crowdfund
  $last_cf = $self->get_crowdfund();

	return $self;
}

sub get_crowdfund {
  my $self = shift;

  my $crowd = undef;
  my $ua = LWP::UserAgent->new;
  my $url = 'https://robertsspaceindustries.com/api/stats/getCrowdfundStats';
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

  my $res = $ua->request($req);
  if (! $res->is_success) {
    $crowd = { 'error' => "Failed to retrieve crowdfund info: " . $res->status_line };
    return $crowd;
  }

  $json = decode_json($res->content);
  $crowd = ${$json}{'data'};
  ${$crowd}{'time'} = time();

  return $crowd;
}

###########################################################################
# check_crowdfund
#
# Retrieve current crowdfund data and then compare to a stored value.
# Report if the any aspect passed a threshold.
###########################################################################
sub check_crowdfund {
  my $self = shift;
  my $report = undef;

  my $new_cf = get_crowdfund();
printf STDERR "%s - Checking %d against %d\n",
  strftime("%Y-%m-%d %H:%M:%S", gmtime()),
  ${$last_cf}{'funds'} / 100.0,
  ${$new_cf}{'funds'} / 100.0;
  if (!defined($new_cf) || defined(${$new_cf}{'error'})) {
    $report = "Crowdfunds check, error: " . ${$new_cf}{'error'};
    return $report;
  }

# Funds passed a threshold ?
  my $funds_t = next_funds_threshold(${$last_cf}{'funds'});
  if (${$new_cf}{'funds'} > $funds_t) {
    # Report to channel
    $report = sprintf("Crowdfund just passed \$%s and is now \$%s", prettyprint(int($funds_t / 100)), prettyprint(int(${$new_cf}{'funds'} / 100)));
  }

# Finish
  $last_cf = $new_cf;
  return $report;
}

# Select a next threshold to test, given a current value
sub next_funds_threshold {
  # NB: this amount is in cents, not dollars
  my $current = shift;

printf STDERR "next_funds_threshold(%d)\n", $current;
  # We'll report at every $100,000 step
  my $t = int($current / 10000000) * 10000000 + 10000000;
printf STDERR "Proposing: %d\n", $t;
  # Except is that's a round million then we want finer reporting,
  # i.e. report at $X,800,000 / $X,900,000 / $X,950,000 / $X,975,000 /
  #                $X,990,000 / $X,995,000 / $X,99[6-9],000
  if ($t == int($current / 100000000) * 100000000 + 100000000) {
    # The next $100k is the next $1m as well, so drop back $50k
    $t = $t - 5000000;
printf STDERR "Proposing: %d\n", $t;
    if ($t < $current) {
    # This is less than current, so bump to $75k
      $t += 2500000;
printf STDERR "Proposing: %d\n", $t;
      if ($t < $current) {
      # This is less than current, so bump to $90k
        $t += 1500000;
printf STDERR "Proposing: %d\n", $t;
        if ($t < $current) {
        # This is less than current, so bump to $95k
          $t += 500000;
printf STDERR "Proposing: %d\n", $t;
          if ($t < $current) {
          # This iless than current, so bump by $1k increments
            while ($t < $current) {
              $t += 100000;
printf STDERR "Proposing: %d\n", $t;
            }
          }
        }
      }
    }
  }

  return $t;
}
###########################################################################

sub get_current_cf {
  my $self = shift;

  my $crowd = get_crowdfund();
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

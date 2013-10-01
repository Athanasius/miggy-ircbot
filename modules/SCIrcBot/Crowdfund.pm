package SCIrcBot::Crowdfund;

use LWP;
use JSON;

my %last_cf = undef;

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

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

  return $crowd;
}

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

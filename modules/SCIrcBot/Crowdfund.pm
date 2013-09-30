package SCIrcBot::Crowdfund;

use LWP;
use JSON;

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

	return $self;
}

sub get_current_cf {
  my $self = shift;

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
    return "Failed to retrieve crowdfund info: " . $res->status_line;
  }

  $json = decode_json($res->content);
  my $crowd = ${$json}{'data'};
  return sprintf("Crowdfund Total: \$%s / Fans: %s / Alpha Slots Left: %s",
    prettyprint(${$crowd}{'funds'} / 100.0),
    prettyprint(${$crowd}{'fans'}),
    prettyprint(${$crowd}{'alpha_slots_left'})
  );
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

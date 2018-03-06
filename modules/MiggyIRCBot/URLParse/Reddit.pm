package MiggyIRCBot::URLParse::Reddit;

use strict;
use warnings;

use POE;
use POE::Component::Client::HTTP;
use HTTP::Request;
use JSON;
use POSIX qw/strftime/;
use Data::Dumper;

my ($reddit_clientid, $reddit_secret, $reddit_username, $reddit_password);
my $reddit_token;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{'http_alias'} = $args{'http_alias'};

#printf STDERR "MiggyIRCBot::URLParse::Reddit->new()\n";
  ($reddit_clientid, $reddit_secret, $reddit_username, $reddit_password) = ($args{'reddit_clientid'}, $args{'reddit_secret'}, $args{'reddit_username'}, $args{'reddit_password'});

  unless ( $self->{http_alias} ) {
    print STDERR "MiggyIRCBot::URLParse::Reddit - Must have an http_alias set up via MiggyIRCBot::HTTP\n";
    return undef;
  }

  $self->{session_id} = POE::Session->create(
    object_states => [
      $self => [ qw(_shutdown _start _get_reddit_auth_token _parse_reddit_auth_token get_reddit_url_info _get_reddit_url_info _parse_reddit_url_info ) ],
    ],
  )->ID();
#printf STDERR "MiggyIRCBot::URLParse::Reddit->new(): Got Session\n";
  unless ( $self->{http_alias} ) {
    die "Must have an http_alias set up via MiggyIRCBot::HTTP\n";
  }
#printf STDERR "MiggyIRCBot::URLParse::Reddit->new(): \$self = %s\n", Dumper($self);

  return $self;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
  $self->{session_id} = $_[SESSION]->ID();
#printf STDERR "MiggyIRCBot::URLParse::Reddit->_start()\n";
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
  $kernel->alias_set('miggyircbot-reddit');
  undef;
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
#printf STDERR "MiggyIRCBot::URLParse::Reddit->_shutdown()\n";
  $kernel->alarm_remove_all();
  $kernel->refcount_decrement( $self->{session_id}, __PACKAGE__ );
  $kernel->call( $self->{http_alias} => 'shutdown' );
  undef;
}

# curl -X POST -d 'grant_type=password&username=Suisanahta&password=Y45s,0y,bAs!' --user 'nf8WmWwJWfzmdg:OZhzCGPCPX72KNHVnQFjq4Axpt8' https://www.reddit.com/api/v1/access_token
sub _get_reddit_auth_token {
  my ($kernel, $heap, $self) = @_[KERNEL, HEAP, OBJECT];
  my %args;
printf STDERR "_GET_REDDIT_AUTH_TOKEN\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

printf STDERR "_GET_REDDIT_AUTH_TOKEN: Requesting new token...\n";
  $heap->{reddit_url} = $args{'url'};
  $heap->{_channel} = $args{'_channel'};
  my $h = HTTP::Headers->new;
  $h->authorization_basic($reddit_clientid, $reddit_secret);
  $h->header('Connection' => 'close', 'Accept-Language' => 'en-gb;q=0.8, en;q=0.7');
  my $req = HTTP::Request->new('POST', 'https://www.reddit.com/api/v1/access_token', $h, 'grant_type=password&username=' . $reddit_username . '&password=' . $reddit_password);
#printf STDERR "_GET_REDDIT_AUTH_TOKEN: Request = '%s'\n", Dumper($req);
  $kernel->post( $self->{http_alias}, 'request', '_parse_reddit_auth_token', $req, \%args);

  undef;
}

sub _parse_reddit_auth_token {
  my ($kernel, $heap, $self, $request, $response) = @_[KERNEL, HEAP, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

printf STDERR "_PARSE_REDDIT_AUTH_TOKEN\n";
  push @params, $self->{session_id};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "_PARSE_REDDIT_AUTH_TOKEN: res != success: $res->status_line\n";
printf STDERR "_PARSE_REDDIT_AUTH_TOKEN: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error = "Failed to parse Reddit auth token response: ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "_PARSE_REDDIT_AUTH_TOKEN: res == success\n";
    if ($res->header('Content-Type') =~ /application\/json/) {
      my $json = decode_json($res->content);
      if (!defined($json->{'access_token'})) {
        push @params, 'irc_miggybot_url_error', $args, "Reddit Auth Token response was JSON, but no access_token";
#printf STDERR "Reddit Auth Token response was JSON, but no access_token:\n%s\n", Dumper($json);
      } else {
        $reddit_token = $json->{'access_token'};
        $args->{'_requested_auth'} = 0;
#printf STDERR "_PARSE_REDDIT_AUTH_TOKEN: token is now '%s'\n", $reddit_token;
        my %args = ( url => $heap->{'reddit_url'}, _channel => $heap->{'_channel'} );
        my @args;
        $args[0] = \%args;
#printf STDERR "_PARSE_REDDIT_AUTH_TOKEN: \@args is %s\n", Dumper(\@args);
        push @params, '_get_reddit_url_info',  $args;
      }
    } else {
      push @params, 'irc_miggybot_url_error', $args, "Reddit Auth Token response wasn't JSON!";
    }
  }

  $kernel->post(@params);
  undef;
}

sub get_reddit_url_info {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
printf STDERR "GET_REDDIT_URL_INFO\n";
  $kernel->post( $self->{session_id}, '_get_reddit_url_info', @_[ARG0..$#_] );
  undef;
}

# curl -H 'Authorization: bearer 17048500-4lUE40xaMAyMDylbJrxVFxa5KTI' -A 'perl:MiggyIRCBOT:v0.01 (by /u/suisanahta)' https://oauth.reddit.com/r/Elitedangerous/comments/2rsnkn/api/info
sub _get_reddit_url_info {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
printf STDERR "_GET_REDDIT_URL_INFO\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
#printf STDERR "_GET_REDDIT_URL_INFO: ARGO is hash ref\n";
     %args = %{ $_[ARG0] };
  } else {
#printf STDERR "_GET_REDDIT_URL_INFO: ARGO is NOT hash ref\n";
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  if (! $reddit_token) {
printf STDERR "_GET_REDDIT_URL_INFO: No auth token, posting to _get_reddit_auth_token...\n";
    $kernel->post( $self->{session_id}, '_get_reddit_auth_token', \%args );
    return undef;
  }

  if (!defined($args{'url'})) {
printf STDERR "_GET_REDDIT_URL_INFO: no URL!\n";
    return 0;
  }
printf STDERR "_GET_REDDIT_URL_INFO: Url '%s'\n", $args{'url'};
  my (undef, $link, $req);
  if ((undef, $link) = $args{'url'} =~ /^http(s)?:\/\/.+\.reddit\.com\/r\/[^\/]+\/comments\/([^\/]+)/) {
#printf STDERR "Url '%s', Link '%s'\n", $args{'url'}, $link;
    $req = HTTP::Request->new('GET', 'https://oauth.reddit.com/by_id/t3_' . $link, ["Authorization" => "bearer " . $reddit_token, "Connection" => "close", 'Accept-Language' => 'en-gb;q=0.8, en;q=0.7' ] );
#printf STDERR "_GET_REDDIT_URL_INFO: Request = '%s'\n", Dumper($req);
  } elsif ((undef, $link) = $args{'url'} =~ /^http(s)?:\/\/.+\.reddit\.com\/r\/([^\/]+)/) {
printf STDERR "Url '%s', Link '%s'\n", $args{'url'}, $link;
    $req = HTTP::Request->new('GET', 'https://oauth.reddit.com/r/' . $link . '/about', ["Authorization" => "bearer " . $reddit_token, "Connection" => "close", 'Accept-Language' => 'en-gb;q=0.8, en;q=0.7' ] );
  }
  $kernel->post( $self->{http_alias}, 'request', '_parse_reddit_url_info', $req, \%args);

  undef;
}

sub _parse_reddit_url_info {
  my ($kernel, $heap, $self, $request, $response) = @_[KERNEL, HEAP, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

printf STDERR "_PARSE_REDDIT_URL_INFO\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "_PARSE_REDDIT_URL_INFO: res != success: %s\n", $res->status_line;
if (defined($res->header('X-PCCH-Errmsg'))) { printf STDERR "_PARSE_REDDIT_URL_INFO: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg'); }
    if ($res->status_line eq "401 Unauthorized") {
printf STDERR "_PARSE_REDDIT_URL_INFO: Got 401, requesting new token\n";
      if (defined($args->{'_requested_auth'}) and $args->{'_requested_auth'} == 1) {
printf STDERR "_GET_REDDIT_AUTH_TOKEN: Here again and already trying to request auth token\n";
        $kernel->post($self->{'session_id'}, 'irc_miggybot_url_error', $args, "No reddit Auth Token, and we've already tried!");
        return undef;
      }
      $args->{'_requested_auth'} = 1;
      $kernel->post( $self->{session_id}, '_get_reddit_auth_token', $args );
      return undef;
    } else {
      my $error = "Failed to parse Reddit API response: ";
      if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
       $error .= $+{'errornum'} . ": " . $+{'errorstr'};
      } else {
       $error .=  $res->status_line;
      }
      push @params, 'irc_miggybot_url_error', $args, $error;
    }
  } else {
#printf STDERR "_PARSE_REDDIT_URL_INFO: res == success\n";
    if ($res->header('Content-Type') =~ /application\/json/) {
#printf STDERR "_PARSE_REDDIT_URL_INFO: Content-Type is application/json\n";
      my $json = decode_json($res->content);
      if (!defined($json->{'data'})) {
printf STDERR "_PARSE_REDDIT_URL_INFO: data is NOT present in JSON\n";
        push @params, 'irc_miggybot_url_error', $args, "Reddit API response was JSON, but no data";
      } else {
#printf STDERR "_PARSE_REDDIT_URL_INFO: data is present in JSON:\n%s\n", Dumper($json);
        my $item = $json->{'data'}{'children'}[0]->{'data'};
        if ($item) {
          my $d = sprintf("[REDDIT] %s (%s) | %d points (%d|%d) | %d comments | Posted by %s", $item->{'title'}, $item->{'subreddit'}, $item->{'ups'} + $item->{'downs'}, $item->{'score'}, $item->{'downs'}, $item->{'num_comments'}, $item->{'author'});
          push @params, 'irc_miggybot_url_success', $args, $d;
        } elsif ($json->{'data'}{'url'}) {
          $item = $json->{'data'};
          chomp($item->{'public_description'});
          my $d = sprintf("[REDDIT] https://www.reddit.com%s \"%s\" | Created: %s | Subscribers: %d | Description: %s", $item->{'url'}, $item->{'title'}, strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($item->{'created_utc'})), $item->{'subscribers'}, $item->{'public_description'});
          push @params, 'irc_miggybot_url_success', $args, $d;
        } else {
          push @params, 'irc_miggybot_url_error', $args, "Reddit API response was JSON, with data, but couldn't find children data";
        }
      }
    } else {
printf STDERR "_PARSE_REDDIT_URL_INFO: Response was NOT JSON\n";
      push @params, 'irc_miggybot_url_error', $args, "Reddit API response wasn't JSON!";
    }
  }

#printf STDERR "_PARSE_REDDIT_URL_INFO: \@params: %s\n", Dumper(\@params);
  $kernel->post(@params);
  undef;
}

1;

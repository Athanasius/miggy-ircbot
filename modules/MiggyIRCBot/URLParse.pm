package MiggyIRCBot::URLParse;

use strict;
use warnings;
use POSIX;
use Data::Dumper;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use HTTP::Request;
use HTML::TreeBuilder;

my %sites = (
  'imgur\.com$' => {get => \&get_generic, parse => \&parse_imgur_com},
  '^www\.youtube\.com$' => {get => \&get_youtube_com, parse => \&parse_youtube_com}
);

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
      $self => [ qw(_shutdown _start _get_url get_generic _parse_url ) ],
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
printf STDERR "_GET_URL\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

printf STDERR "_GET_URL: URL '%s'\n", $args{'url'};
  my ($host) = $args{'url'} =~ /^http[s]?:\/\/([^\/:]+)(:[0-9]+)?\//;
printf STDERR "_GET_URL: Host '%s'\n", $host;
  my $done;
  foreach my $site (keys(%sites)) {
printf STDERR "_GET_URL: Checking site '%s'\n", $site;
    if ($host =~ $site) {
printf STDERR "_GET_URL: Recognised a %s site...\n"; #\t%s\n", $site, Dumper(${sites}{$site});
      $sites{$site}->{'get'}->($kernel, $self, \%args);
      $done = 1;
      last;
    }
  }

  if (! $done) {
#printf STDERR "_GET_URL: posting to http_alias\n";
    $kernel->post( $self->{session_id}, 'get_generic', @_[ARG0..$#_] );
  }

  undef;
}

sub get_generic {
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
  $kernel->post( $self->{http_alias}, 'request', '_parse_url', $req, \%args );
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
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "_PARSE_URL: res == success\n";
    # Check if it's a site we have a special handler for
printf STDERR "_PARSE_URL: args->{url} = '%s'\n", $args->{'url'};
    my ($host) = $args->{'url'} =~ /^http[s]?:\/\/([^\/:]+)(:[0-9]+)?\//;
    my $done;
    foreach my $site (keys(%sites)) {
      if ($host =~ $site) {
printf STDERR "_PARSE_URL: Recognised a %s site...\n", $site;
        my $blurb = $sites{$site}->{'parse'}($res, $args);
        if (defined($blurb)) {
          push @params, 'irc_miggybot_url_success', $args, $blurb;
        } else {
          push @params, 'irc_miggybot_url_error', $args, "'$args->{'url'} confused me!";
        }
        $done = 1;
        last;
      }
    }

    if (!defined($done)) {
      # Use generic parsing
      if ($res->header('Content-Type') =~ /^text\/(ht|x)ml/) {
        my $tree = HTML::TreeBuilder->new;
        $tree->parse($res->decoded_content);
        $tree->eof();
        my $title = $tree->look_down('_tag', 'title');
        if ($title) {
          push @params, 'irc_miggybot_url_success', $args, "[ " . $title->as_text . " ] - " . $host;
        } else {
          push @params, 'irc_miggybot_url_error', $args, "No <title> found in URL content";
        }
      # } elsif (image) {
      } else {
        $args->{'quiet'} = 1;
        push @params, 'irc_miggybot_url_success', $args, "That was not an HTML page";
      }
    }
  }

#for my $p (@params) { printf STDERR " param = $p\n"; }
  $kernel->post(@params);
  undef;
}

sub parse_imgur_com {
  my ($res, $args) = @_;

# imgur.com is a PITA, fills in <title> etc after the fact with javascript
# waste of time to respond with the generic page title
## 16:25:35 <bigp3rm-> NASA just released an image of the new planet 168:http://imgur.com/yfTAqXq
## 16:25:36 <EDBot> [ New images of Planet 9 worrying for scientists. - Imgur ] - imgur.com
  return "";
}

sub get_youtube_com {
  my ($kernel, $self, $args) = @_;

#printf STDERR "\t%s\n", Dumper($kernel);
  $kernel->post( $self->{session_id}, 'get_generic', $args );
}

# 21:02:28<EDBot> [YouTube] Title: The Good, The Bad and The Bucky: Highlights from the Buckyball Run | Uploader: Esvandiary | Uploaded: 2015-05-15 00:47:44 UTC | Duration: 00:07:13 | Views: 1,591 | Comments: 7 | Likes: 39 | Dislikes: 1
sub parse_youtube_com {
  my ($res, $args) = @_;

  my $blurb = "";
  if ($res->header('Content-Type') =~ /^text\/(ht|x)ml/) {
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($res->decoded_content);
    $tree->eof();
    my $title = $tree->look_down('_tag', 'title');
    if (! $title) {
      return $blurb;
    }
    $blurb = "[ YouTube ] Title: " . $title->as_text;

    my $yt_user_info = $tree->look_down('_tag' => 'div', 'class' => 'yt-user-info');
    if ($yt_user_info) {
      my $a = $yt_user_info->look_down('_tag' => 'a');
      if ($a) {
        $blurb .= " | Uploader: " . $a->as_text;
      }
    }

    my $datePublished = $tree->look_down('_tag' => 'meta', 'itemprop' => 'datePublished');
    if ($datePublished) {
      $blurb .= " | Uploaded: " . $datePublished->attr('content');
    }

    my $duration = $tree->look_down('_tag' => 'meta', 'itemprop' => 'duration');
    if ($duration) {
      my $d = $duration->attr('content');
      my ($min, $sec, $hour) = $d =~ /^PT([0-9]+)M([0-9]+)S$/;
      if ($min >= 60) {
        $hour = int($min / 60);
        $min -= $hour * 60;
      } else {
        $hour = 0;
      }
      $blurb .= sprintf " | Duration: %02d:%02d:%02d", $hour, $min, $sec;
    }

    my $interactionCount = $tree->look_down('_tag' => 'meta', 'itemprop' => 'interactionCount');
    if ($interactionCount) {
      $blurb .= " | Views: " . prettyprint($interactionCount->attr('content'));
    }

    if ($title) {
      return $blurb;
    } else {
      return undef;
    }
  # } elsif (image) {
  } else {
    $args->{'quiet'} = 1;
    return "That was not an HTML page";
  }
  return undef;
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

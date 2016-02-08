package MiggyIRCBot::URLParse;

use strict;
use warnings;
use POSIX;
use Data::Dumper;

use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use MiggyIRCBot::URLParse::Reddit;
use HTTP::Request;
use HTML::TreeBuilder;
use URI::Escape;
use JSON;
use Date::Parse;

my $youtube_api_key;
my ($imgur_clientid, $imgur_clientsecret);
my ($reddit_clientid, $reddit_secret, $reddit_username, $reddit_password);
my $reddit;
my $twitchtv_clientid;
my %sites = (
  '^http(s)?:\/\/www\.youtube\.com\/watch\?v=' => {get => \&get_youtube_com, parse => \&parse_youtube_com},
  '^http(s)?:\/\/youtu\.be\/' => {get => \&get_youtube_com, parse => \&parse_youtube_com},
  '^http(s)?:\/\/www\.youtube\.com\/user\/.+\/live' => {get => \&get_youtube_com, parse => \&parse_youtube_com},
  '^http(s)?:\/\/(i\.)?imgur\.com\/([^\.\/]+)(\..+)?$' => {get => \&get_imgur_image, parse => \&parse_imgur_image},
  '^http(s)?:\/\/imgur\.com\/a\/([^\.\/]+)$' => {get => \&get_imgur_album, parse => \&parse_imgur_album},
  '^http(s)?:\/\/imgur\.com\/gallery\/([^\.\/]+)$' => {get => \&get_imgur_gallery, parse => \&parse_imgur_gallery },
  '^http(s)?:\/\/community\.elitedangerous\.com\/galnet\/uid\/[a-f0-9]+$' => {get => undef, parse => \&parse_community_elitedangeros_com_galnet_uid },
  '^http(s)?:\/\/coriolis\.io\/outfit\/' => {get => \&get_coriolis_io_outfit, parse => undef },
  '^http(s)?:\/\/www\.reddit\.com\/r\/[^\/]+\/comments\/[^\/]+' => {get => \&get_reddit_com, parse => undef },
  '^http(s)?:\/\/www\.reddit\.com\/r\/[^\/]+' => {get => \&get_reddit_com, parse => undef },
  '^http(s)?:\/\/www\.twitch\.tv\/.+' => { get => \&get_twitch_tv, parse => undef },

## Ignores
  # http://s2.quickmeme.com/img/7e/7e05cfb0d554c683769a319b95183ccc84f74d226488b8f3de7bd00b240d2bc1.jpg
  '^http(s)?:\/\/(.+\.)?quickmeme\.com\/.+\.[^\.]{3}$' => { get => \&ignore_url, parse => undef },
  # http://eliteraretrader.co.uk/?route=66,52,23,72,62,51,83,99,71,8,9,87,58,10,26,29,65,20,101,4,98,49,28,96,48,37,38,24,93,75,46,44,60,89,55,77,79,30,1,36,13,84,31,25,6,81,70,18,47,67,68,73,63,14,3,43,91,92,33,27,64,80,45,22,19,97,41,86,16,66&name=Full%20Optimized
  '^http(s)?:\/\/eliteraretrader\.co\.uk\/' => { get => \&ignore_url, parse => undef },
  # http://lmgtfy.com/?q=...
  '^http(s)?:\/\/lmgtfy\.com\/\?q=' => { get => \&ignore_url, parse => undef },
  # http://prntscr.com/9rqz2w
  '^http(s)?:\/\/prntscr\.com\/.+' => { get => \&ignore_url, parse => undef },

);

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;

printf STDERR "MiggyIRCBot::URLParse->new()\n";
  $youtube_api_key = $args{'youtube_api_key'};
  ($imgur_clientid, $imgur_clientsecret) = ($args{'imgur_clientid'}, $args{'imgur_clientsecret'});
  ($reddit_clientid, $reddit_secret, $reddit_username, $reddit_password) = ($args{'reddit_clientid'}, $args{'reddit_secret'}, $args{'reddit_username'}, $args{'reddit_password'});
  $twitchtv_clientid = $args{'twitchtv_clientid'};

	return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
#printf STDERR "MiggyIRCBot::URLParse->PCI_register()\n";
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );

  unless ( $self->{http_alias} ) {
    $self->{http_alias} = join('-', 'ua-miggyircbot', $irc->session_id() );
    $self->{follow_redirects} ||= 2;
    POE::Component::Client::HTTP->spawn(
      Alias           => $self->{http_alias},
      Agent           => 'perl:MiggyIRCBOT:v0.01 (by /u/suisanahta)',
      #Agent           => 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/39.0.2171.71 Safari/537.36',
      FollowRedirects => $self->{follow_redirects},
    );
  }

  $self->{session_id} = POE::Session->create(
    object_states => [
      $self => [ qw(_shutdown _start _get_url get_generic _parse_url parse_youtube_api parse_imgur_image parse_imgur_album parse_imgur_gallery parse_twitch_tv_stream parse_twitch_tv_channel parse_twitch_tv_video ) ],
    ],
  )->ID();
  $poe_kernel->state( 'get_url', $self );

  $reddit = MiggyIRCBot::URLParse::Reddit->new(
    reddit_clientid     => $reddit_clientid,
    reddit_secret       => $reddit_secret,
    reddit_username     => $reddit_username,
    reddit_password     => $reddit_password,
  );
#printf STDERR "reddit -> %s\n", Dumper($reddit);

  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
#printf STDERR "MiggyIRCBot::URLParse->PCI_unregister()\n";
  $poe_kernel->state( 'get_url' );
  $poe_kernel->call( $self->{session_id} => '_shutdown' );
  delete $self->{irc};
  return 1;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
#printf STDERR "MiggyIRCBot::URLParse->_start()\n";
  $self->{session_id} = $_[SESSION]->ID();
  $kernel->refcount_increment( $self->{session_id}, __PACKAGE__ );
  undef;
}

sub _shutdown {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
#printf STDERR "MiggyIRCBot::URLParse->_shutdown()\n";
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

printf STDERR "_GET_URL: URL '%s'\n", $args{'url'};
  my $done;
  foreach my $site (keys(%sites)) {
#printf STDERR "_GET_URL: Checking site '%s'\n", $site;
    if ($args{'url'} =~ $site and ${$sites{$site}}{'get'}) {
printf STDERR "_GET_URL: Recognised a %s site...\n", $site; #\t%s\n", $site, Dumper(${sites}{$site});
      $sites{$site}->{'get'}->($kernel, $self, \%args);
      $done = 1;
      last;
    }
  }

  if (! $done) {
#printf STDERR "_GET_URL: posting to get_generic\n";
    $kernel->post( $self->{session_id}, 'get_generic', @_[ARG0..$#_] );
  }

  undef;
}

sub get_generic {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
#printf STDERR "GET_GENERIC\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  # If you don't add the 'Connection: close' header than a HTTP/1.1 server
  # with a long persistent connection timeout will mean you don't actually
  # get your full response until it closes the connection.
  my $req = HTTP::Request->new('GET', $args{'url'}, ['Connection' => 'close']);
mylog("_GET_GENERIC: '", $args{'url'}, "'");
#printf STDERR "GET_GENERIC: req is:\n%s\n", $req->as_string();
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
printf STDERR "_PARSE_URL: res != success: %s\n", $res->status_line;
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
printf STDERR "_PARSE_URL: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_sc_url_error', $args, $error;
  } else {
#printf STDERR "_PARSE_URL: res == success\n";
    # Check if it's a site we have a special handler for
#printf STDERR "_PARSE_URL: args->{url} = '%s'\n", $args->{'url'};
    my ($host) = $args->{'url'} =~ /^http[s]?:\/\/([^\/:]+)(:[0-9]+)?\//;
    my $done;
    foreach my $site (keys(%sites)) {
      if ($args->{'url'} =~ $site) {
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
          push @params, 'irc_miggybot_url_success', $args, "[ " . trunc_str($title->as_text, 400) . " ] - " . $host;
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


###########################################################################
# www.youtube.com parsing for video URLs
###########################################################################
sub get_youtube_com {
  my ($kernel, $self, $args) = @_;

  my (undef, undef, $video_id) = $args->{'url'} =~ /^http(s)?:\/\/(www\.youtube\.com\/watch\?v=|youtu\.be\/)([^\?&]+)/;
#printf STDERR "GET_YOUTUBE_COM: video_id = %s\n", $video_id;
  if ($youtube_api_key and $video_id) {
printf STDERR "GET_YOUTUBE_COM, using API for '%s'\n", $args->{'url'};
    my $req = HTTP::Request->new('GET', "https://www.googleapis.com/youtube/v3/videos?part=contentDetails%2Cstatistics%2Csnippet&id=" . $video_id . "&key=" . $youtube_api_key, ['Connection' => 'close']);
    $kernel->post( $self->{http_alias}, 'request', 'parse_youtube_api', $req, $args );
  } else {
printf STDERR "GET_YOUTUBE_COM, using scraping for '%s'\n", $args->{'url'};
    # If not a specific video
    my $req = HTTP::Request->new('GET', $args->{'url'}, ['Connection' => 'close']);
    $kernel->post( $self->{http_alias}, 'request', '_parse_url', $req, $args );
  }
}

sub parse_youtube_api {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "PARSE_YOUTUBE_API\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_YOUTUBE_API: res != success: $res->status_line\n";
printf STDERR "PARSE_YOUTUBE_API: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_YOUTUBE_API success!\n";
    my $json = decode_json($res->content);
    if (! $json) {
#printf STDERR "PARSE_YOUTUBE_API no JSON\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_YOUTUBE_API got JSON\n";
      if (defined($json->{'items'}) and defined($json->{'items'}[0]->{'id'})) {
#printf STDERR "PARSE_YOUTUBE_API got items and it contains id\n";
        my $v = $json->{'items'}[0];
# 21:02:28<EDBot> [YouTube] Title: The Good, The Bad and The Bucky: Highlights from the Buckyball Run | Uploader: Esvandiary | Uploaded: 2015-05-15 00:47:44 UTC | Duration: 00:07:13 | Views: 1,591 | Comments: 7 | Likes: 39 | Dislikes: 1
        my $blurb = "[ YouTube ] Title: " . trunc_str($v->{'snippet'}{'title'}, 256);
        $blurb .= " | Uploader: " . $v->{'snippet'}{'channelTitle'};
        my $pub_timet = str2time($v->{'snippet'}{'publishedAt'});
        if (defined($v->{'contentDetails'}{'duration'})) {
          $blurb .= youtube_parse_duration($v->{'contentDetails'}{'duration'});
        }
        if (defined($v->{'statistics'}{'viewCount'})) {
          $blurb .= " | Views: " . prettyprint($v->{'statistics'}{'viewCount'});
        }
        if (defined($v->{'statistics'}{'commentCount'})) {
          $blurb .= " | Comments: " . prettyprint($v->{'statistics'}{'commentCount'});
        }
        if (defined($v->{'statistics'}{'likeCount'})) {
          $blurb .= " | Likes: " . prettyprint($v->{'statistics'}{'likeCount'});
        }
        if (defined($v->{'statistics'}{'dislikeCount'})) {
          $blurb .= " | Dislikes: " . prettyprint($v->{'statistics'}{'dislikeCount'});
        }
        if (defined($pub_timet)) {
          $blurb .= " | Uploaded: " . strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($pub_timet));
        }
#printf STDERR "PARSE_YOUTUBE_API pushing blurb to params\n";
        push @params, 'irc_miggybot_url_success', $args, $blurb;
      } else {
#printf STDERR "PARSE_YOUTUBE_API no items?\n";
        push @params, 'irc_miggybot_url_error', $args, "No items? Content '" . $res->content . "'";
      }
    }
  }

  $kernel->post(@params);
  undef;
}

## Fallback parser in case we don't have a YouTube API key, or it's just
## not a URL for a specific video
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
    $blurb .= youtube_parse_duration($duration->attr('content'));

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

sub youtube_parse_duration {
  my $d = shift;

  # PT2H7M20S
  my ($hstring, $hour, $min, $sec) = $d =~ /^PT(([0-9]+)H)?([0-9]+)M([0-9]+)S$/;
#printf STDERR "youtube_parse_duration: Duration '%s' %s %s %s %s\n", $d, $hstring, $hour, $min, $sec;
  if (!defined($min)) {
printf STDERR "Can't find minute in Duration '%s' %s, %s, %s, %s\n", $d, $hstring, $hour, $min, $sec;
    return "";
  }
  if ($min >= 60) {
    $hour = int($min / 60);
    $min -= $hour * 60;
  } elsif (!defined($hour)) {
    $hour = 0;
  }
  return sprintf " | Duration: %02d:%02d:%02d", $hour, $min, $sec;
}
###########################################################################

###########################################################################
# IMGUR URL Parsing
###########################################################################
sub get_imgur_image {
  my ($kernel, $self, $args) = @_;

  my (undef, undef, $image_id) = $args->{'url'} =~ /^http(s)?:\/\/(i\.)?imgur\.com\/([^\.]+)(\..+)?$/;
#printf STDERR "GET_IMGUR_IMAGE: image_id = %s\n", $image_id;
  if ($imgur_clientid and $image_id) {
printf STDERR "GET_IMGUR_IMAGE, using API for '%s' (%s)\n", $args->{'url'}, $image_id;
    my $req = HTTP::Request->new('GET', "https://api.imgur.com/3/image/" . $image_id, ['Authorization' => 'Client-ID ' . $imgur_clientid, 'Connection' => 'close']);
#printf STDERR "GET_IMGUR_IMAGE: req is:\n%s\n", $req->as_string();
    $kernel->post( $self->{http_alias}, 'request', 'parse_imgur_image', $req, $args );
  } else {
printf STDERR "GET_IMGUR_IMAGE, NOT just using scraping for '%s', no output\n", $args->{'url'};
  }
}

sub parse_imgur_image {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "PARSE_IMGUR_IMAGE\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_IMGUR_IMAGE: res != success: $res->status_line\n";
printf STDERR "PARSE_IMGUR_IMAGE: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_IMGUR_IMAGE: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_IMGUR_IMAGE: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_IMGUR_IMAGE: Got JSON?\n";
      if (!defined($json->{'success'}) or $json->{'success'} ne 'true') {
#printf STDERR "PARSE_IMGUR_IMAGE: No success, or it's not true?\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'data'}{'error'};
      } elsif (defined($json->{'data'})) {
#printf STDERR "PARSE_IMGUR_IMAGE: success == true\n";
#printf STDERR "PARSE_IMGUR_IMAGE: Content: '%s'\n", Dumper($json);
        my $d = $json->{'data'};
        if (defined($d->{'title'}) or defined($d->{'description'}) or (defined($d->{'nsfw'}) and $d->{'nsfw'} eq 'true')) {
          my $blurb = "[ Imgur Image ] - ";
          if (defined($d->{'title'})) {
            $blurb .= "Title: " . trunc_str($d->{'title'}, 256);
          } else {
            $blurb .= "<no title>";
          }
          if (defined($d->{'nsfw'}) and $d->{'nsfw'} eq 'true') {
            $blurb .= " | *NSFW*";
          }
          if (defined($d->{'animated'}) and $d->{'animated'} eq 'true') {
            $blurb .= " | *ANIMATED*";
          }
          if (defined($d->{'description'})) {
            $blurb .= " | Description: " . trunc_str($d->{'description'}, 256);
          }
          if (defined($d->{'account_url'})) {
            $blurb .= " | User: " . $d->{'account_url'};
          }
          if (defined($d->{'views'})) {
            $blurb .= " | Views: " . $d->{'views'};
          }
          if (defined($d->{'size'})) {
            $blurb .= " | Size: " . prettyprint($d->{'size'});
          }
          if (defined($d->{'section'}) and $d->{'section'} ne "") {
            $blurb .= " | Section: " . $d->{'section'};
          }
          if (defined($d->{'datetime'})) {
            $blurb .= " | Published: " . strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($d->{'datetime'}));
          }
#printf STDERR "PARSE_IMGUR_IMAGE: pushing blurb\n";
          push @params, 'irc_miggybot_url_success', $args, $blurb;
        } else {
          mylog("parse_imgur_image: Nothing interesting for '", $args->{'url'}, "'");
          return undef;
        }
      }
    }
  }

#printf STDERR "PARSE_IMGUR_IMAGE: \@params = %s\n", Dumper(\@params);
  $kernel->post(@params);
  undef;
}

## Albums
sub get_imgur_album {
  my ($kernel, $self, $args) = @_;

  my (undef, $album_id) = $args->{'url'} =~ /^http(s)?:\/\/imgur\.com\/a\/([^\.\/]+)$/;
printf STDERR "GET_IMGUR_ALBUM: album_id = %s\n", $album_id;
  if ($imgur_clientid and $album_id) {
printf STDERR "GET_IMGUR_ALBUM, using API for '%s' (%s)\n", $args->{'url'}, $album_id;
    my $req = HTTP::Request->new('GET', "https://api.imgur.com/3/album/" . $album_id, ['Authorization' => 'Client-ID ' . $imgur_clientid, 'Connection' => 'close']);
#printf STDERR "GET_IMGUR_ALBUM: req is:\n%s\n", $req->as_string();
    $kernel->post( $self->{http_alias}, 'request', 'parse_imgur_album', $req, $args );
  } else {
printf STDERR "GET_IMGUR_ALBUM, NOT just using scraping for '%s', no output\n", $args->{'url'};
  }
}

sub parse_imgur_album {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

printf STDERR "PARSE_IMGUR_ALBUM\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_IMGUR_ALBUM: res != success: $res->status_line\n";
printf STDERR "PARSE_IMGUR_ALBUM: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_IMGUR_ALBUM: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_IMGUR_ALBUM: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_IMGUR_ALBUM: Got JSON?\n";
      if (!defined($json->{'success'}) or $json->{'success'} ne 'true') {
#printf STDERR "PARSE_IMGUR_ALBUM: No success, or it's not true?\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'data'}{'error'};
      } elsif (defined($json->{'data'})) {
#printf STDERR "PARSE_IMGUR_ALBUM: success == true\n";
        my $d = $json->{'data'};
        my $blurb = "[ Imgur Album ] - ";
        if (defined($d->{'title'})) {
          $blurb .= "Title: " . trunc_str($d->{'title'}, 256);
        } else {
          $blurb .= "<no title>";
        }
        if (defined($d->{'nsfw'}) and $d->{'nsfw'} eq 'true') {
          $blurb .= " | *NSFW* ";
        }
        if (defined($d->{'description'})) {
          $blurb .= " | Description: " . trunc_str($d->{'description'}, 256);
        }
        if (defined($d->{'account_url'})) {
          $blurb .= " | User: " . $d->{'account_url'};
        }
        if (defined($d->{'images_count'})) {
          $blurb .= " | # Images: " . prettyprint($d->{'images_count'});
        }
        if (defined($d->{'views'})) {
          $blurb .= " | Views: " . $d->{'views'};
        }
        if (defined($d->{'section'}) and $d->{'section'} ne "") {
          $blurb .= " | Section: " . $d->{'section'};
        }
        if (defined($d->{'datetime'})) {
          $blurb .= " | Published: " . strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($d->{'datetime'}));
        }
#printf STDERR "PARSE_IMGUR_ALBUM: pushing blurb\n";
        push @params, 'irc_miggybot_url_success', $args, $blurb;
      }
    }
  }

#printf STDERR "PARSE_IMGUR_ALBUM: \@params = %s\n", Dumper(\@params);
  $kernel->post(@params);
  undef;
}

## Galleries
sub get_imgur_gallery {
  my ($kernel, $self, $args) = @_;

  my (undef, $gallery_id) = $args->{'url'} =~ /^http(s)?:\/\/imgur\.com\/gallery\/([^\.\/]+)$/;
printf STDERR "GET_IMGUR_GALLERY: gallery_id = %s\n", $gallery_id;
  if ($imgur_clientid and $gallery_id) {
printf STDERR "GET_IMGUR_GALLERY, using API for '%s' (%s)\n", $args->{'url'}, $gallery_id;
    my $req = HTTP::Request->new('GET', "https://api.imgur.com/3/gallery/" . $gallery_id, ['Authorization' => 'Client-ID ' . $imgur_clientid, 'Connection' => 'close']);
#printf STDERR "GET_IMGUR_GALLERY: req is:\n%s\n", $req->as_string();
    $kernel->post( $self->{http_alias}, 'request', 'parse_imgur_gallery', $req, $args );
  } else {
printf STDERR "GET_IMGUR_GALLERY, NOT just using scraping for '%s', no output\n", $args->{'url'};
  }
}

sub parse_imgur_gallery {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

printf STDERR "PARSE_IMGUR_GALLERY\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_IMGUR_GALLERY: res != success: $res->status_line\n";
printf STDERR "PARSE_IMGUR_GALLERY: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_IMGUR_GALLERY: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_IMGUR_GALLERY: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_IMGUR_GALLERY: Got JSON?\n";
      if (!defined($json->{'success'}) or $json->{'success'} ne 'true') {
#printf STDERR "PARSE_IMGUR_GALLERY: No success, or it's not true?\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'data'}{'error'};
      } elsif (defined($json->{'data'})) {
#printf STDERR "PARSE_IMGUR_GALLERY: success == true\n";
        my $d = $json->{'data'};
        my $blurb = "[ Imgur Gallery ] - ";
        if (defined($d->{'title'})) {
          $blurb .= "Title: " . trunc_str($d->{'title'}, 256);
        } else {
          $blurb .= "<no title>";
        }
        if (defined($d->{'account_url'}) and $d->{'account_url'} ne 'null') {
          $blurb .= " | User: " . $d->{'account_url'};
        }
        if (defined($d->{'nsfw'}) and $d->{'nsfw'} eq 'true') {
          $blurb .= " | *NSFW* ";
        }
        if (defined($d->{'description'})) {
          $blurb .= " | Description: " . trunc_str($d->{'description'}, 256);
        }
        if (defined($d->{'images_count'})) {
          $blurb .= " | # Images: " . prettyprint($d->{'images_count'});
        }
        if (defined($d->{'views'})) {
          $blurb .= " | Views: " . $d->{'views'};
        }
        if (defined($d->{'section'}) and $d->{'section'} ne "") {
          $blurb .= " | Section: " . $d->{'section'};
        }
        if (defined($d->{'datetime'})) {
          $blurb .= " | Published: " . strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($d->{'datetime'}));
        }
#printf STDERR "PARSE_IMGUR_GALLERY: pushing blurb\n";
        push @params, 'irc_miggybot_url_success', $args, $blurb;
      }
    }
  }

#printf STDERR "PARSE_IMGUR_GALLERY: \@params = %s\n", Dumper(\@params);
  $kernel->post(@params);
  undef;
}
###########################################################################

###########################################################################
# https://community.elitedangerous.com/galnet/uid/...
###########################################################################
sub parse_community_elitedangeros_com_galnet_uid {
  my ($res, $args) = @_;

#printf STDERR "_PARSE_COMMUNITY_ELITEDANGEROS_COM_GALNET_UID\n";
  my $blurb = "";
  if ($res->header('Content-Type') =~ /^text\/(ht|x)ml/) {
#printf STDERR "_PARSE_COMMUNITY_ELITEDANGEROS_COM_GALNET_UID\n\tGot HTML or XML reply\n";
#printf STDERR $res->content, "\n";
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($res->decoded_content);
    $tree->eof();
    my $title = $tree->look_down('_tag' => 'h3', 'class' => qr/.*galnetNewsArticleTitle.*/);
    if (! $title) {
printf STDERR "_PARSE_COMMUNITY_ELITEDANGEROS_COM_GALNET_UID\n\tNo galnetNewsArticleTitle\n";
      return undef;
    }

    my $galnet_title = $title->look_down('_tag' => 'a');
    if ($galnet_title) {
#printf STDERR "_PARSE_COMMUNITY_ELITEDANGEROS_COM_GALNET_UID\n\tFound galnet title text\n";
      return sprintf("[ %s ] - Elite Dangerous GalNet (community.elitedangerous.com/galnet)", trunc_str($galnet_title->as_text, 256)) ;
    }

  # } elsif (image) {
  } else {
    $args->{'quiet'} = 1;
    return "That was not an HTML page";
  }
  return undef;
}
###########################################################################

###########################################################################
# http://coriolis.io/outfit/vulture/04A5A4A3D5A4D3C1e1e000304064a2b272525.Iw19kA==.MwRgDMZSIEz7cMZA?bn=KWS
#
#  We don't actually retrieve the URL at all (the page is all JS driven),
# instead just pick some things out of the URL.
###########################################################################
sub get_coriolis_io_outfit {
  my ($kernel, $self, $args) = @_;
  my @params;
  push @params, $args->{session};

printf STDERR "_GET_CORIOLIS_IO_OUTFIT: url '%s'\n", $args->{'url'};
  my $blurb = "";
  if ($args->{'url'} =~ /^http(s)?:\/\/coriolis\.io\/outfit\/(?<ship_name>[^\/]+)\/[^\?]*(\?bn=(?<build_name>.+))?$/) {
#printf STDERR "_GET_CORIOLIS_IO_OUTFIT: matches regex\n";
    if (defined($+{'ship_name'})) {
      my $sn = $+{'ship_name'};
#printf STDERR "_GET_CORIOLIS_IO_OUTFIT: got ship_name\n";
      if (defined($+{'build_name'})) {
#printf STDERR "_GET_CORIOLIS_IO_OUTFIT: got build_name\n";
        my $bn = $+{'build_name'};
        # For some reason coriolios.io double-encodes / characters in build names
        $bn =~ s/%252F/\//g;
        $blurb = "[ " . $sn . " - " . uri_unescape($bn) . " ] - coriolis.io";
      } else {
#printf STDERR "_GET_CORIOLIS_IO_OUTFIT: but no build_name\n";
        $blurb = "[ " . $sn . " ] - coriolis.io";
      }
    } else {
printf STDERR "_GET_CORIOLIS_IO_OUTFIT: no ship_name\n";
      $blurb =  "[ Coriolis Shipyard ] - coriolis.io";
    }
  } else {
printf STDERR "_GET_CORIOLIS_IO_OUTFIT: does NOT match regex\n";
    $blurb =  "[ Coriolis Shipyard ] - coriolis.io";
  }
  push @params, 'irc_miggybot_url_success', $args, $blurb;

  $kernel->post(@params);
  undef;
}
###########################################################################

###########################################################################
# get_reddit_com
###########################################################################
sub get_reddit_com {
  my ($kernel, $self, $args) = @_;
#printf STDERR "GET_REDDIT_COM\n";

  $kernel->post('miggyircbot-reddit', 'get_reddit_url_info', $args);

  undef;
}
###########################################################################

###########################################################################
# twitch.tv
###########################################################################
sub get_twitch_tv {
  my ($kernel, $self, $args) = @_;
#printf STDERR "GET_TWITCH_TV\n";

  my (undef, $channel_name, $video_pre, $video_id) = $args->{'url'} =~ /^http(s)?:\/\/www\.twitch\.tv\/([^\/]+)(\/dashboard)?$/;
#printf STDERR "GET_TWITCH_TV: channel_name = %s\n", $channel_name;
  if ($twitchtv_clientid and $channel_name) {
printf STDERR "GET_TWITCH_TV, using API for '%s' (%s)\n", $args->{'url'}, $channel_name;
    my $req = HTTP::Request->new('GET', "https://api.twitch.tv/kraken/streams/" . $channel_name, ['Accept' => 'application/vnd.twitchtv.3+json', 'Client-ID' => $twitchtv_clientid, 'Connection' => 'close']);
#printf STDERR "GET_TWITCH_TV: req is:\n%s\n", $req->as_string();
    $args->{'_channel_name'} = $channel_name;
    $kernel->post( $self->{http_alias}, 'request', 'parse_twitch_tv_stream', $req, $args );
  } elsif ((undef, $channel_name, $video_pre, $video_id) = $args->{'url'} =~ /^http(s)?:\/\/www\.twitch\.tv\/([^\/]+)\/(.+)\/([0-9]+)$/) {
printf STDERR "GET_TWITCH_TV, using API for '%s' (%s%s)\n", $args->{'url'}, $video_pre, $video_id;
    my $req = HTTP::Request->new('GET', "https://api.twitch.tv/kraken/videos/" . $video_pre . $video_id, ['Accept' => 'application/vnd.twitchtv.3+json', 'Client-ID' => $twitchtv_clientid, 'Connection' => 'close']);
    $args->{'_channel_name'} = $channel_name;
    $args->{'_video_pre'} = $video_pre;
    $args->{'_video_id'} = $video_id;
    $kernel->post( $self->{http_alias}, 'request', 'parse_twitch_tv_video', $req, $args );
  } else {
printf STDERR "GET_TWITCH_TV, NOT just using scraping for '%s', no output\n", $args->{'url'};
  }
}

sub parse_twitch_tv_stream {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "PARSE_TWITCH_TV_STREAM\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_TWITCH_TV_STREAM: res != success: $res->status_line\n";
printf STDERR "PARSE_TWITCH_TV_STREAM: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_TWITCH_TV_STREAM: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_TWITCH_TV_STREAM: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_TWITCH_TV_STREAM: Got JSON?\n";
      if (defined($json->{'error'})) {
printf STDERR "PARSE_TWITCH_TV_STREAM: error!\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'message'};
      } elsif (!defined($json->{'stream'})) {
printf STDERR "PARSE_TWITCH_TV_STREAM: No stream, offline?  Trying for channel info instead.\n";
        my $req = HTTP::Request->new('GET', "https://api.twitch.tv/kraken/channels/" . $args->{'_channel_name'}, ['Accept' => 'application/vnd.twitchtv.3+json', 'Client-ID' => $twitchtv_clientid, 'Connection' => 'close']);
#printf STDERR "PARSE_TWITCH_TV_STREAM: channel req is:\n%s\n", $req->as_string();
        $kernel->post( $self->{http_alias}, 'request', 'parse_twitch_tv_channel', $req, $args );
        return undef;
      } else {
#printf STDERR "PARSE_TWITCH_TV_STREAM: success == true\n";
#printf STDERR "PARSE_TWITCH_TV_STREAM: Content: '%s'\n", Dumper($json);
        my $blurb = "[ Twitch.TV ] - " . $json->{'stream'}->{'channel'}->{'display_name'} . " *LIVE*";
        my $more_blurb .= make_twitch_tv_blurb($json->{'stream'}->{'channel'});
        if (defined($more_blurb)) {
          push @params, 'irc_miggybot_url_success', $args, $blurb . $more_blurb;
          $kernel->post(@params);
        }
      }
    }
  }

  undef;
}

sub parse_twitch_tv_channel {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "PARSE_TWITCH_TV_CHANNEL\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_TWITCH_TV_CHANNEL: res != success: $res->status_line\n";
printf STDERR "PARSE_TWITCH_TV_CHANNEL: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_TWITCH_TV_CHANNEL: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_TWITCH_TV_CHANNEL: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_TWITCH_TV_CHANNEL: Got JSON?\n";
      if (defined($json->{'error'})) {
printf STDERR "PARSE_TWITCH_TV_CHANNEL: error!\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'message'};
      } else {
#printf STDERR "PARSE_TWITCH_TV_CHANNEL: success == true\n";
#printf STDERR "PARSE_TWITCH_TV_CHANNEL: Content: '%s'\n", Dumper($json);
        my $blurb = "[ Twitch.TV ] - " . $json->{'display_name'} . " (offline)";
        my $more_blurb .= make_twitch_tv_blurb($json, $args);
        if (defined($more_blurb)) {
          push @params, 'irc_miggybot_url_success', $args, $blurb . $more_blurb;
          $kernel->post(@params);
        }
      }
    }
  }

  undef;
}

sub parse_twitch_tv_video {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;

#printf STDERR "PARSE_TWITCH_TV_VIDEO\n";
  push @params, $args->{session};
  my $res = $response->[0];

  if (! $res->is_success) {
printf STDERR "PARSE_TWITCH_TV_VIDEO: res != success: $res->status_line\n";
printf STDERR "PARSE_TWITCH_TV_VIDEO: X-PCCH-Errmsg: %s\n", $res->header('X-PCCH-Errmsg');
    my $error =  "Failed to retrieve URL - ";
    if (defined($res->header('X-PCCH-Errmsg')) and $res->header('X-PCCH-Errmsg') =~ /Connection to .* failed: [^\s]+ error (?<errornum>\?\?|[0-9]]+): (?<errorstr>.*)$/) {
      $error .= $+{'errornum'} . ": " . $+{'errorstr'};
    } else {
      $error .=  $res->status_line;
    }
    push @params, 'irc_miggybot_url_error', $args, $error;
  } else {
#printf STDERR "PARSE_TWITCH_TV_VIDEO: Content: '%s'\n", $res->content;
    my $json = decode_json($res->content);
    if (!defined($json)) {
#printf STDERR "PARSE_TWITCH_TV_VIDEO: No JSON?\n";
      push @params, 'irc_miggybot_url_error', $args, "Failed to parse JSON response";
    } else {
#printf STDERR "PARSE_TWITCH_TV_VIDEO: Got JSON?\n";
      if (defined($json->{'error'})) {
printf STDERR "PARSE_TWITCH_TV_VIDEO: error!\n";
        push @params, 'irc_miggybot_url_error', $args, "JSON failed: " . $json->{'message'};
      } else {
#printf STDERR "PARSE_TWITCH_TV_VIDEO: success == true\n";
#printf STDERR "PARSE_TWITCH_TV_VIDEO: Content: '%s'\n", Dumper($json);
        my $blurb = "[ Twitch.TV ] - " . $json->{'channel'}->{'display_name'} . " (Saved Video)";
        my $more_blurb .= make_twitch_tv_blurb($json, $args);
        if (defined($more_blurb)) {
          push @params, 'irc_miggybot_url_success', $args, $blurb . $more_blurb;
          $kernel->post(@params);
        }
      }
    }
  }

  undef;
}

sub make_twitch_tv_blurb {
  my ($d) = @_;
  my $blurb = undef;

  if (defined($d->{'status'}) or defined($d->{'game'})) {
    $blurb = "";
    if (defined($d->{'game'})) {
      $blurb .= " | Game: " . $d->{'game'};
    }
    if (defined($d->{'title'})) {
      $blurb .= " | Title: " . $d->{'title'};
    }
    if (defined($d->{'status'}) and $d->{'status'} ne "recorded") {
      $blurb .= " | Status: " . $d->{'status'};
    }
    if (defined($d->{'length'})) {
      $blurb .= " | Duration: " . time_seconds_pretty($d->{'length'});
    }
    if (defined($d->{'views'})) {
      $blurb .= " | Views: " . $d->{'views'};
    }
    if (defined($d->{'followers'})) {
      $blurb .= " | Followers: " . $d->{'followers'};
    }
    if (defined($d->{'recorded_at'})) {
      $blurb .= " | Recorded: " . iso8601_datetime_pretty($d->{'recorded_at'});
    }
  }

  return $blurb;
}
###########################################################################

###########################################################################
# Ignore URLs
###########################################################################
sub ignore_url {
  my ($kernel, $self, $args) = @_;

  printf "Ignoring URL '%s'\n", $args->{'url'};

  undef;
}
###########################################################################

###########################################################################
# Misc helper subs
###########################################################################
sub prettyprint {
  my $number = sprintf "%.0f", shift @_;
  # Add one comma each time through the do-nothing loop
  1 while $number =~ s/^(-?\d+)(\d\d\d)/$1,$2/;
  # Put the dollar sign in the right place
  #$number =~ s/^(-?)/$1\$/;
  $number;
}

sub trunc_str {
  my ($line, $len) = @_;

  if (length($line) <= $len) {
    return $line;
  }

  return substr($line, 0, $len - 3) . "...";
}

sub time_seconds_pretty {
  my $secs = shift;

  my ($hours, $minutes, $seconds);

  $hours = int($secs / 3600);
  $secs -= $hours * 3600;

  $minutes = int($secs / 60);
  $secs -= $minutes * 60;

  $seconds = $secs;

  return sprintf("%02d:%02d:%02d", $hours, $minutes, $seconds);
}

sub iso8601_datetime_pretty {
  my $ts = shift;

  my $uts = str2time($ts, "UTC");
  if (!defined($uts)) {
    return $ts;
  }
  return strftime("%Y-%m-%d %H:%M:%S %Z", gmtime($uts));
}

sub mylog {
  printf STDERR "%s - %s\n", strftime("%Y-%m-%d %H:%M:%S UTC", gmtime()), join("", @_);
}
###########################################################################

1;

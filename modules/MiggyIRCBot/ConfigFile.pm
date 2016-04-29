package MiggyIRCBot::ConfigFile;

require Exporter;
@EXPORT = qw(&config %irc);

use Config::ApacheFormat;

### our %config = (
###   'nickname' => 'Cmdr^Jameson',
###   'ircname' => 'Commander Jameson - *the* original commander',
###   'channel' => '#elite-dangerous',
###   'ircserver' => 'irc.quakenet.org',
###   'ircport' => 6667,
###   'connect_delay' => 60,
###   'ready_message' => 'Reporting for duty!',
###   'console_port' => 3337,
###   'console_password' => 'UnwindLamps',
###   'seen_filestore' => 'seen_filestore.db',
###   'no_http_proxy' => '',
###   'rss_url' => 'https://miggy.org/games/elite-dangerous/devtracker/ed-dev-posts.rss',
###   'rss_filestore' => 'rss.db',
###   'rss_check_time' => 300,
###   'qauth' => '',
###   'qpass' => '',
###   'youtube_api_key' => '',
###   'imgur_clientid' => '',
###   'imgur_clientsecret' => '',
###   'reddit_clientid' => '',
###   'reddit_secret' => '',
###   'reddit_username' => '',
###   'reddit_password' => '',
###   'reddit_authorization_redirect' => '',
### );

sub new {
  my ($class, %args) = @_;
	my $self = {};
  $self->{config} = undef;
  bless ($self, $class);
  my $file = $args{'file'};

  $self->{config} = Config::ApacheFormat->new(
    setenv_vars => 1,
    duplicate_directives => "error",
    valid_blocks => [ qw (
      BotConfig
        Irc
          Server
            Auth
        Channel
        Http
        Seen
        Rss
          Feed
        UrlParser
          YouTube
          Imgur
          Reddit
          Twitch
    ) ],
    valid_directives => [ qw (
      SetEnv
      NickName
      IrcName
      Name
      Port
      ConnectDelay
      Type
      Password
      ReadyMessage
      FileStore
      Url
      CheckInterval
      ApiKey
      ClientId
      ClientSecret
      UserName
      AuthorizationRedirect
    ) ],
  );
  $self->{config}->read($file);

  if (! $self->{config}->block('BotConfig') ) {
    warn("Config file didn't yield a BotConfig");
    return undef;
  }
  $self->{botconfig} = $self->{config}->block('BotConfig');
  return $self;
}

sub config {
  my $self = shift;

  return $self->{config};
}

sub irc {
  my $self = shift;
  my $field = shift;

  my $irc = $self->{botconfig}->block('Irc');
  return $irc->get($field);
}

########################################################################
# Per-Field retrieval
########################################################################
sub nickname {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->get('NickName');
}
########################################################################

1;

package MiggyIRCBot::ConfigFile;

require Exporter;
@EXPORT = qw(&config &irc
  &NickName
  &IrcName
  &ServerName
  &ServerPort
  &ServerConnectDelay
  &ServerAuth
  &Channel
  &Http
  &SeenFileStore
  &Rss
  &UrlParser
  &CrowdFund
);

use Config::ApacheFormat;

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
        CrowdFund
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

########################################################################
# Per-Field retrieval
########################################################################
## BotConfig -> Irc
sub NickName {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->get('NickName');
}

sub IrcName {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->get('IrcName');
}

## BotConfig -> Irc -> Server
sub ServerName {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->block('Server')->get('Name');
}

sub ServerPort {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->block('Server')->get('Port');
}

sub ServerConnectDelay {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->block('Server')->get('ConnectDelay');
}

## BotConfig -> Irc -> Server -> Auth
sub ServerAuth {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->block('Server')->block('Auth');
}

## BotConfig -> Channel
sub Channel {
  my $self = shift;

  return $self->{botconfig}->block('Channel');
}

## BotConfig -> Http
sub Http {
  my $self = shift;

  return $self->{botconfig}->block('Irc')->block('Http');
}

## BotConfig -> Seen
sub Seen {
  my $self = shift;

  return $self->{botconfig}->block('Seen');
}

## BotConfig -> Rss
sub Rss {
  my $self = shift;

  return $self->{botconfig}->block('Rss');
}

## BotConfig -> Rss -> Feed
## BotConfig -> UrlParser
sub UrlParser {
  my $self = shift;

  return $self->{botconfig}->block('UrlParser');
}
## BotConfig -> UrlParser -> Youtube
## BotConfig -> UrlParser -> Imgur
## BotConfig -> UrlParser -> Reddit
## BotConfig -> UrlParser -> Twitch
########################################################################

## BotConfig -> CrowdFund
sub CrowdFund {
  my $self = shift;

  return $self->{botconfig}->block('CrowdFund');
}

########################################################################

1;

package MiggyIRCBot::ConfigFile;

our %config = (
  'nickname' => 'Cmdr^Jameson',
  'ircname' => 'Commander Jameson - *the* original commander',
  'channel' => '#elite-dangerous',
  'ircserver' => 'irc.quakenet.org',
  'ircport' => 6667,
  'connect_delay' => 60,
  'ready_message' => 'Reporting for duty!',
  'console_port' => 3337,
  'console_password' => 'UnwindLamps',
  'seen_filestore' => 'seen_filestore.db',
  'crowdfund_funds_check_time' => 300,
  'crowdfund_url' => 'https://robertsspaceindustries.com/api/stats/getCrowdfundStats',
  'rss_url' => 'https://robertsspaceindustries.com/comm-link/rss',
  'no_http_proxy' => '',
  'rss_filestore' => 'rss.db',
  'rss_check_time' => 300,
  'qauth' => '',
  'qpass' => '',
  'youtube_api_key' => '',
  'imgur_clientid' => '',
  'imgur_clientsecret' => '',
  'reddit_clientid' => '',
  'reddit_secret' => '',
  'reddit_username' => '',
  'reddit_password' => '',
  'reddit_authorization_redirect' => '',
);

sub new {
  my ($class, %args) = @_;
	my $self = bless {}, $class;
  my $file = $args{'file'};

	if (!open(CF, "<$file")) {
    printf STDERR "Failed to open file '%s' to read config\n", $file;
    return undef;
  }
  my $line = 0;
  while (<CF>) {
    $line++;
    chomp;
    if (/^\#/) {
      next;
    } elsif (/^nickname:\s+(.*)$/i) {
      $config{'nickname'} = $1;
    } elsif (/^ircname:\s+(.*)$/i) {
      $config{'ircname'} = $1;
    } elsif (/^channel:\s+(.*)$/i) {
      $config{'channel'} = $1;
    } elsif (/^ircserver:\s+(.*)$/i) {
      $config{'ircserver'} = $1;
    } elsif (/^ircport:\s+(.*)$/i) {
      $config{'ircport'} = $1;
    } elsif (/^connect_delay:\s+(.*)$/i) {
      $config{'connect_delay'} = $1;
    } elsif (/^ready_message:\s+(.*)$/i) {
      $config{'ready_message'} = $1;
    } elsif (/^console_port:\s+(.*)$/i) {
      $config{'console_port'} = $1;
    } elsif (/^console_password:\s+(.*)$/i) {
      $config{'console_password'} = $1;
    } elsif (/^seen_filestore:\s+(.*)$/i) {
      $config{'seen_filestore'} = $1;
    } elsif (/^no_http_proxy:\s+(.*)$/i) {
      $config{'no_http_proxy'} = $1;
    } elsif (/^crowdfund_funds_check_time:\s+(.*)$/i) {
      $config{'crowdfund_funds_check_time'} = $1;
    } elsif (/^crowdfund_url:\s+(.*)$/i) {
      $config{'crowdfund_url'} = $1;
    } elsif (/^rss_url:\s+(.*)$/i) {
      $config{'rss_url'} = $1;
    } elsif (/^rss_filestore:\s+(.*)$/i) {
      $config{'rss_filestore'} = $1;
    } elsif (/^rss_check_time:\s+(.*)$/i) {
      $config{'rss_check_time'} = $1;
    } elsif (/^qauth:\s+(.*)$/i) {
      $config{'qauth'} = $1;
    } elsif (/^qpass:\s+(.*)$/i) {
      $config{'qpass'} = $1;
    } elsif (/^youtube_api_key:\s+(.*)$/i) {
      $config{'youtube_api_key'} = $1;
    } elsif (/^imgur_clientid:\s+(.*)$/i) {
      $config{'imgur_clientid'} = $1;
    } elsif (/^imgur_clientsecret:\s+(.*)$/i) {
      $config{'imgur_clientsecret'} = $1;
    } elsif (/^reddit_clientid:\s+(.*)$/i) {
      $config{'reddit_clientid'} = $1;
    } elsif (/^reddit_secret:\s+(.*)$/i) {
      $config{'reddit_secret'} = $1;
    } elsif (/^reddit_username:\s+(.*)$/i) {
      $config{'reddit_username'} = $1;
    } elsif (/^reddit_password:\s+(.*)$/i) {
      $config{'reddit_password'} = $1;
    } elsif (/^reddit_authorization_redirect:\s+(.*)$/i) {
      $config{'reddit_authorization_redirect'} = $1;
    } elsif (/^twitchtv_clientid:\s+(.*)$/i) {
      $config{'twitchtv_clientid'} = $1;
    } else {
      printf STDERR "Unknown field in config file '%s', line %d : %s\n", $file, $line, $_;
    }
  }
  close(CF);

	return $self;
}

sub getconf {
  my $self = shift;
  my $field = shift;

  #printf STDERR "ConfigFile::getconf: field = '%s', which is: %s\n", $field, $config{$field};
  return $config{$field};
}

1;

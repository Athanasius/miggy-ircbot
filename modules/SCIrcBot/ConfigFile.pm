package SCIrcBot::ConfigFile;

our %config = (
  'nickname' => '^Lumi^',
  'ircname' => 'Henri Lumi, the helpful 300i pilot',
  'channel' => '#keep-nicks',
  'ircserver' => 'irc.quakenet.org',
  'ircport' => 6667,
  'connect_delay' => 60,
  'console_port' => 3337,
  'console_password' => 'UnwindLamps',
  'seen_filestore' => 'seen_filestore.db',
  'crowdfund_funds_check_time' => 300,
  'rss_url' => 'https://robertsspaceindustries.com/comm-link/rss',
  'rss_filestore' => 'rss.db',
  'rss_check_time' => 300,
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
    } elsif (/^console_port:\s+(.*)$/i) {
      $config{'console_port'} = $1;
    } elsif (/^console_password:\s+(.*)$/i) {
      $config{'console_password'} = $1;
    } elsif (/^seen_filestore:\s+(.*)$/i) {
      $config{'seen_filestore'} = $1;
    } elsif (/^crowdfund_funds_check_time:\s+(.*)$/i) {
      $config{'crowdfund_funds_check_time'} = $1;
    } elsif (/^rss_url:\s+(.*)$/i) {
      $config{'rss_url'} = $1;
    } elsif (/^rss_filestore:\s+(.*)$/i) {
      $config{'rss_filestore'} = $1;
    } elsif (/^rss_check_time:\s+(.*)$/i) {
      $config{'rss_check_time'} = $1;
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

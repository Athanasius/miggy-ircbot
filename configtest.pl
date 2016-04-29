#!/usr/bin/perl -w -Imodules
# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab

use MiggyIRCBot::ConfigFile;
use Data::Dumper;

my $config = MiggyIRCBot::ConfigFile->new(file => "bot.cfg");

print STDERR "Got past MiggyIRCBot::ConfigFile->new\n";

if (! $config) {
  die("Failed to load config!");
}

#print Dumper($config);

#print Dumper(\%ENV);

#print Dumper($config->conf->block("BotConfig")), "\n";
my $nickname = $config->NickName;
if ($nickname) {
  printf "NickName: %s\n", $nickname;
} else {
  print STDERR "No NickName!\n";
}

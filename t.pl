#!/usr/bin/perl -w -Imodules -Ishare/perl/5.14.2
use strict;
use warnings;

use Data::Dumper;

use POSIX qw/strftime/;
use Date::Language;
use Date::Parse;
my $lang = Date::Language->new("English");

$ENV{'TZ'} = 'CST6CDT';
my $t = $lang->str2time("Thu Oct 10 18:30:00");
$ENV{'TZ'} = 'UTC';
print strftime("%Y-%m-%d %H:%M:%S %Z\n", localtime($t));

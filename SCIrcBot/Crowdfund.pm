# vim: textwidth=0 wrapmargin=0 shiftwidth=2 tabstop=2 expandtab
package SCIrcBot::Crowdfund;

use warnings;
use strict;

my $last_query = 0;

sub new {
  my $self = {};
  bless($self);
  return $self;
}

1;

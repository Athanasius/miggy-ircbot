package MiggyIRCBot::RSS;

use strict;
use warnings;
use POE;
use POE::Component::Client::HTTP;
use POE::Component::IRC::Plugin qw(:ALL);
use XML::RSS;
use HTTP::Request;
use DBI;
use DBD::SQLite;
use POSIX qw/strftime/;

our %rss_items;
our $rss_url;
our $rss_file;
our $rss_db;

sub new {
  my ($class, %args) = @_;
  my $self = bless {}, $class;
  $self->{'http_alias'} = $args{'http_alias'};
  $rss_url = $args{'rss_url'};
  $rss_file = $args{'rss_file'};

  # Fire up the SQLite DB, and read in current data
  $rss_db = DBI->connect("dbi:SQLite:dbname=$rss_file","","");
  my $sth = $rss_db->prepare("SELECT * FROM rss_items");
  $sth->execute();
  while (my $row = $sth->fetchrow_hashref) {
    $rss_items{${$row}{'guid'}} = $row;
  }

  return $self;
}

sub PCI_register {
  my ($self,$irc) = @_;
  $self->{irc} = $irc;
  $irc->plugin_register( $self, 'SERVER', qw(spoof) );

printf STDERR "MiggyIRCBot::RSS->PCI_register()\n";
  unless ( $self->{http_alias} ) {
    print STDERR "MiggyIRCBot::RSS - Must have an http_alias set up via MiggyIRCBot::HTTP\n";
    return undef;
  }

  $self->{session_id} = POE::Session->create(
    object_states => [
      $self => [ qw(_shutdown _start _get_rss_items _parse_rss_items _get_rss_latest) ],
    ],
  )->ID();
  $poe_kernel->state( 'get_rss_items', $self );
  $poe_kernel->state( 'get_rss_latest', $self );
  return 1;
}

sub PCI_unregister {
  my ($self,$irc) = splice @_, 0, 2;
  $poe_kernel->state( 'get_rss_latest' );
  $poe_kernel->state( 'get_rss_items' );
  $poe_kernel->call( $self->{session_id} => '_shutdown' );
  delete $self->{irc};
  return 1;
}

sub _start {
  my ($kernel,$self) = @_[KERNEL,OBJECT];
printf STDERR "MiggyIRCBot::RSS->_start()\n";
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

###########################################################################
# Code to handle getting RSS items and storing them in local hash, which
# is also tied to a database file.
#
# get_rss_items(): User-command trigger for testing
# get_rss_latest(): User-command to return latest item details
# rss_check(): Perform a timed RSS check
# _get_rss_items(): Actually retrieve current items
# _parse_rss_items(): Triggered when we receive items back.  Check which ones
#                 are new and fire them at irc_miggybot_rss_newitems
###########################################################################
sub get_rss_items {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
#printf STDERR "GET_ITEMS\n";

  mylog("GET_RSS_ITEMS: Posting to __GET_RSS_ITEMS");
  $kernel->post( $self->{session_id}, '_get_rss_items', @_[ARG0..$#_] );
  undef;
}

sub _get_rss_items {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
  mylog("__GET_RSS_ITEMS: called");
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;
  mylog("_GET_RSS_ITEMS: posting to http_alias");
  $kernel->post( $self->{http_alias}, 'request', '_parse_rss_items', HTTP::Request->new('GET', $rss_url, ['Connection' => 'close', 'Accept-Language' => 'en-gb;q=0.8, en;q=0.7'] ), \%args );
  undef;
}

sub _parse_rss_items {
  my ($kernel, $self, $request, $response) = @_[KERNEL, OBJECT, ARG0, ARG1];
  my $args = $request->[1];
  my @params;
  mylog("_PARSE_RSS_ITEMS: called");
  push @params, $args->{session};
  my $result = $response->[0];
  if ( $result->is_success ) {
    if (!defined($result->header('Content-Type')) or $result->header('Content-Type') ne "application/rss+xml") {
      mylog("_PARSE_RSS_ITEMS: Bad Content-Type");
      my $ct;
      if (!defined($result->header('Content-Type')) or $result->header('Content-Type') eq "") {
        mylog("_PARSE_RSS_ITEMS: !defined or empty Content-Type");
        $ct = "<empty>";
      } else {
        $ct = $result->header('Content-Type');
        mylog("_PARSE_RSS_ITEMS: Bad Content-Type is '" . $result->header('Content-Type') . "'");
      }
      push(@params, 'irc_miggybot_rss_error', $args, "Incorrect Content-Type: " . $ct);
    } elsif ($result->content !~ /<rss version/) {
      push(@params, 'irc_miggybot_rss_error', $args, "No RSS tag/version");
    } else {
      my $str = $result->content;
      #mylog("_PARSE_RSS_ITEMS: String to be parsed is\n'" . $str . "'\n\n");
      my $rss = XML::RSS->new();
      eval { $rss->parse($str); };
      if ($@) {
        push @params, 'irc_miggybot_rss_error', $args, $@;
        mylog("_PARSE_RSS_ITEMS: Error from XML::RSS->parse()\n", $str, "\n\n");
      } else {
        my $sth = $rss_db->prepare("INSERT INTO rss_items (title,link,description,author,category,comments,enclosure,guid,pubdate,source,content) VALUES(?,?,?,?,?,?,?,?,?,?,?)");
        push @params, 'irc_miggybot_rss_newitems', $args;
        # reverse() should mean we insert latest item as the highest ID in the DB
        foreach my $item (reverse(@{$rss->{'items'}})) {
#         print "title: $item->{'title'}\n";
#         print "link: $item->{'link'}\n";
          if (!defined($rss_items{$item->{'permaLink'}})) {
#           print " IS NEW!\n";
            $rss_items{$item->{'permaLink'}} = $item;
            push @params, $item;

            my %rss_item = ( 'title' => "NULL", 'link' => "NULL", 'description' => "NULL", 'author' => "NULL", 'category' => "NULL", 'comments' => "NULL", 'enclosure' => "NULL", 'guid' => "NULL", 'pubdate' => "NULL", 'source' => "NULL", 'content' => "NULL" );
            foreach my $f (keys($item)) {
#             print "Item field: " . $f . " = '" . $item->{$f} . "'\n";
              if ($f eq "permaLink") {
                $rss_item{'guid'} = $item->{$f};
              } elsif ($f eq "pubDate") {
                $rss_item{'pubdate'} = $item->{$f};
              } elsif ($f eq "content") {
                $rss_item{$f} = ${$item->{$f}}{'encoded'};
#               foreach my $c (keys($item->{$f})) {
#                 print "Content field: " . $c . " = '" . ${$item->{$f}}{$c} . "'\n";
#               }
              } else {
                $rss_item{$f} = $item->{$f};
              }
            }
            $sth->execute($rss_item{'title'}, $rss_item{'link'}, $rss_item{'description'}, $rss_item{'author'}, $rss_item{'category'}, $rss_item{'comments'}, $rss_item{'enclosure'}, $rss_item{'guid'}, $rss_item{'pubdate'}, $rss_item{'source'}, $rss_item{'content'});
            mylog("_PARSE_RSS_ITEMS: Should have just INSERTed item: '" . join("', '", $rss_item{'title'}, $rss_item{'link'}, $rss_item{'author'}, $rss_item{'guid'}, $rss_item{'pubdate'}) . "'");
          }
        }
      }
    }
  } else {
    push @params, 'irc_miggybot_rss_error', $args, $result->status_line;
  }
  $kernel->post( @params );
  undef;
}

sub get_rss_latest {
  my ($kernel,$self,$session) = @_[KERNEL,OBJECT,SESSION];
#printf STDERR "GET_ITEMS\n";
  $kernel->post( $self->{session_id}, '_get_rss_latest', @_[ARG0..$#_] );
  undef;
}

sub _get_rss_latest {
  my ($kernel, $self) = @_[KERNEL, OBJECT];
  my %args;
#printf STDERR "_GET_RSS_LATEST\n";
  if ( ref $_[ARG0] eq 'HASH' ) {
     %args = %{ $_[ARG0] };
  } else {
     %args = @_[ARG0..$#_];
  }
  $args{lc $_} = delete $args{$_} for grep { !/^_/ } keys %args;

  my @params;
  push @params, $args{session};

  my $sth = $rss_db->prepare("SELECT * FROM rss_items ORDER BY id DESC LIMIT 10");
#printf STDERR "_GET_RSS_LATEST: Executing query\n";
  my $res = $sth->execute();
  my $pushed;
  while (my $row = $sth->fetchrow_hashref) {
    if (!defined($pushed)) {
#printf STDERR "_GET_RSS_LATEST: Got at least one row\n";
      push @params, 'irc_miggybot_rss_latest', \%args;
    }
    push @params, $row;
    $pushed = 1;
#printf STDERR "_GET_RSS_LATEST: Pushed one row...\n";
  }
  if (!defined($pushed)) {
printf STDERR "_GET_RSS_LATEST: No data?\n";
    push @params, 'irc_miggybot_rss_error', \%args, "Coudn't retrieve latest RSS item from local database";
  }
  $kernel->post( @params );

  undef;
}
###########################################################################

###########################################################################
# Misc. helper sub-routines
###########################################################################
sub mylog {
  printf STDERR "%s - %s\n", strftime("%Y-%m-%d %H:%M:%S UTC", gmtime()), @_;
}
###########################################################################
1;

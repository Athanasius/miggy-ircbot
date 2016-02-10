package POE::Component::IRC::Plugin::QuakenetAuth;
BEGIN {
#  $POE::Component::IRC::Plugin::QuakenetAuth::AUTHORITY = 'cpan:HINRIK';
#}
#{
  $POE::Component::IRC::Plugin::QuakenetAuth::VERSION = '0.01';
}

use strict;
use warnings FATAL => 'all';
use Carp;
use IRC::Utils qw( uc_irc parse_user );
use POE::Component::IRC::Plugin qw( :ALL );

sub new {
    my ($package) = shift;
    croak "$package requires an even number of arguments" if @_ & 1;
    my %self = @_;

    die "$package requires a AuthName" if !defined $self{AuthName};
    die "$package requires a Password" if !defined $self{Password};
    return bless \%self, $package;
}

sub PCI_register {
    my ($self, $irc) = @_;
    $self->{nick} = $irc->{nick};
    $self->{irc} = $irc;
    $irc->plugin_register($self, 'SERVER', qw(isupport nick notice));
    return 1;
}

sub PCI_unregister {
    return 1;
}

# we identify after S_isupport so that pocoirc has a chance to turn on
# CAPAB IDENTIFY-MSG (if the server supports it) before the AutoJoin
# plugin joins channels
sub S_isupport {
    my ($self, $irc) = splice @_, 0, 2;
    $irc->yield(privmsg => "Q\@Cserve.quakenet.org AUTH $self->{AuthName} $self->{Password}");
    return PCI_EAT_NONE;
}

# FIXME: Maybe do this using the following message instead?
# irc_396:  'servercentral.il.us.quakenet.org' 'qauth.users.quakenet.org :is now your hidden host' [qauth.users.quakenet.org, is now your hidden host]
sub S_notice {
    my ($self, $irc) = splice @_, 0, 2;
    my $sender    = parse_user(${ $_[0] });
    my $recipient = parse_user(${ $_[1] }->[0]);
    my $msg       = ${ $_[2] };

    return PCI_EAT_NONE if $recipient ne $irc->nick_name();
    return PCI_EAT_NONE if $sender !~ /^Q$/i;
    return PCI_EAT_NONE if $msg !~ /^You are now logged in as .+\.$/;
    $irc->send_event_next('irc_identified');
    return PCI_EAT_NONE;
}

1;
=encoding utf8

=head1 NAME

POE::Component::IRC::Plugin::QuakenetAuth - A PoCo-IRC plugin which identifies with NickServ when needed

=head1 SYNOPSIS

 use POE::Component::IRC::Plugin::QuakenetAuth;

 $irc->plugin_add( 'QuakenetAuth', POE::Component::IRC::Plugin::QuakenetAuth->new(
     AuthName => 'qauthname',
     Password => 'opensesame'
 ));

=head1 DESCRIPTION

POE::Component::IRC::Plugin::QuakenetAuth is a L<POE::Component::IRC|POE::Component::IRC>
plugin. It auths with Q on connect.

B<Note>: If you have use usermod +x to hide your host and don't want
your real host to be seen at all, make sure you don't join channels
until after you've authed yourself. If you use the L<AutoJoin
plugin|POE::Component::IRC::Plugin::AutoJoin>, it will be taken care of
for you.

=head1 METHODS

=head2 C<new>

Arguments:

B<'AuthName'>, the Q auth name.

B<'Password'>, the Q auth password.

Returns a plugin object suitable for feeding to
L<POE::Component::IRC|POE::Component::IRC>'s plugin_add() method.

=head1 OUTPUT EVENTS

=head2 C<irc_identified>

This event will be sent when you have authed with Q. No arguments
are passed with it.

=head1 AUTHOR

Athanasius, <code@miggy.org>, based on the NickServID module by
Hinrik E<Ouml>rn SigurE<eth>sson, hinrik.sig@gmail.com

=cut

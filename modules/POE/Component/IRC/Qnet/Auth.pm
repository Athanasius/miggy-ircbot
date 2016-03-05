package POE::Component::IRC::Qnet::Auth;
BEGIN {
#  $POE::Component::IRC::Qnet::Auth::AUTHORITY = 'cpan:HINRIK';
#}
#{
  $POE::Component::IRC::Qnet::Auth::VERSION = '0.01';
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

sub S_isupport {
    my ($self, $irc) = splice @_, 0, 2;
    $irc->yield(qbot_auth => $self->{AuthName} => $self->{Password});
    return PCI_EAT_NONE;
}

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

POE::Component::IRC::Qnet::Auth - A PoCo-IRC plugin which identifies with NickServ when needed

=head1 SYNOPSIS

 use POE::Component::IRC::Qnet::Auth;

 $irc->plugin_add( 'Qnet::Auth', POE::Component::IRC::Qnet::Auth->new(
     AuthName => 'qauthname',
     Password => 'opensesame'
 ));

=head1 DESCRIPTION

POE::Component::IRC::Qnet::Auth is a L<POE::Component::IRC|POE::Component::IRC>
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

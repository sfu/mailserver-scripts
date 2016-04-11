#! /usr/local/bin/perl
#
# wakeCreatedir.pl : A program to wake up the createdir inetd process.
#
# Changes
# -------
#

use IO::Socket;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

$CREATEDIRHOST = "rm-rstar1.sfu.ca";
$CREATEDIRPORT = 6081;

my $socket = IO::Socket::INET->new(
    PeerAddr => $CREATEDIRHOST,
    PeerPort => $CREATEDIRPORT,
    Proto    => "tcp",
    Type     => SOCK_STREAM
  )
  or cleanexit(
"Couldn't connect to createdir daemon on $CREATEDIRHOST/$CREATEDIRPORT: $@\n"
  );
my $res = $socket->getline;
close $socket;
cleanexit($res) unless $res =~ /^ok/;
exit 0;

sub cleanexit {
    my ($msg) = @_;
    print STDERR $msg if $msg;
    exit 1;
}

sub EXITHANDLER {
    system 'stty', 'echo';
    &cleanexit("Got signal. \n\nAborted");
}


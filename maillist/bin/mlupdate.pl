#!/usr/bin/perl 
#
# mlupdate.pl : A program run via inetd and/or cron to update the maillist 
#                files.
#
# Add to inetd.conf as:
# mlupdate	stream	tcp	nowait	amaint	/path/to/mlupdate.pl	mlupdate
# Add to services:
# mlupdate 6087/tcp
#
# Rob Urquhart    Jan 15, 2007
# Changes
# -------
#       

use Socket;
use Getopt::Std;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use MLUpdt;
use MLUtils;
use LOCK;
require 'getopts.pl';
use vars qw($main::MLDIR $main::TOKEN $main::SERVICE $opt_h $opt_a);

select(STDOUT); $| = 1;         # make unbuffered
$SIG{INT}  = 'IGNORE';
$SIG{HUP}  = 'IGNORE';
$SIG{QUIT} = 'IGNORE';
$SIG{PIPE} = 'IGNORE';
$SIG{STOP} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{TERM} = 'IGNORE';

getopts('avth') or ( &printUsage && exit(0) );

if ($opt_h) {
   &printUsage;
   exit(0);
}
$main::MLROOT = $MAILLISTDIR;
$main::TEST = $opt_t ? $opt_t : 0;
$main::VERBOSE = $opt_v ? $opt_v : $main::TEST;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
$main::LOGFILE = "${main::MLROOT}/logs/mlupdt.log"; 
open STDOUT, ">>${main::LOGFILE}" or die "Can't redirect STDOUT";
open STDERR, ">&STDOUT" or die "Can't dup STDOUT";
$main::MLDIR = "${main::MLROOT}/files";
$main::UPDATEALL_LOCK = "${main::MLROOT}/mlupdate-a.lock";

# Note, the URL below won't work as it relies on Rob's machine. Need to define new URL for use with MLRestClient
# For now, it'll use prod maillist WO app calls but place files in temp location
if ($main::TEST) {
        # *SOAP::Deserializer::typecast = sub {shift; return shift};
	# $main::SERVICEURL = "http://icat-rob-macpro.its.sfu.ca:60666/cgi-bin/WebObjects/Maillist.woa/ws/MLWebService";
	_stdout( "MLROOT: ${main::MLROOT}\n" );
	unless (-e $main::MLROOT) {
		mkdir $main::MLROOT;
		mkdir "${main::MLROOT}/logs";
		mkdir "${main::MLROOT}/files";
	}
}

if ($opt_a) {
	if (lockInUse($main::UPDATEALL_LOCK)) {
		_stdout( "mlupdate -a process already running. Quitting." );
		exit 0;
	}
	acquire_lock( $main::UPDATEALL_LOCK );
	_stdout( "Starting updateAllMaillists" );
	&updateAllMaillists;
	_stdout( "updateAllMaillists done" );
	release_lock( $main::UPDATEALL_LOCK );
	exit 0;
}

$main::listname = shift @ARGV;
if ($main::listname) {
    # script is being run from command-line with a supplied listname.
    _stdout( "Updating ${main::listname} from command line" );
	updateMaillistFiles($main::listname);
	exit 0;
}

# We are being run via inetd. 
# Only accept connections from localhost, garibaldi, and my test hosts

unless ($main::TEST) {
	my $sockaddr = 'S n a4 x8';
	my $peersockaddr = getpeername(STDIN);
	my ($family, $port, $peeraddr) = unpack($sockaddr, $peersockaddr);
	my ($a, $b, $c, $d) = unpack('C4', $peeraddr);
	my $peer = "$a.$b.$c.$d";
	my ($peername, $aliases, $addrtype, $length, @addrs) = gethostbyaddr($peeraddr, AF_INET);
	
	if (!( $peername =~ /^garibaldi.nfs.sfu.ca/ || 
		   $peername =~ /^garibaldi1.nfs.sfu.ca/ ||
		   $peername =~ /^garibaldi2.nfs.sfu.ca/ ||
		   $peername =~ /^garibaldi3.nfs.sfu.ca/ ||
		   $peername =~ /^garibaldi4.nfs.sfu.ca/ ||
		   $peername =~ /^garibaldi3.tier2.sfu.ca/ ||
		   $peername =~ /^garibaldi4.tier2.sfu.ca/ ||
		   $peername =~ /^bigwhite.ucs.sfu.ca/ ||
		   $peername =~ /^northface.ucs.sfu.ca/ ||
		   $peername =~ /^localhost/ ||
		   $peername =~ /^rm-rstar.sfu.ca/ )) { 
		_stdout( "Connection not allowed from $peername!" );
		exit 0; 
	} 
}

# Get the maillist name from stdin

$listname = lc <>;
$listname =~ s/\s*$//;
if (length($listname) == 0) {
    _stdout( "No listname supplied" );
    exit 0;
}

if ($listname =~ /^([-\w]+)$/) {
    $listname = $1;              # untaint username (only contains word chars)
}
else {
    _stdout( "Bad data in listname: $listname" );
    exit 0;
}

_stdout("Updating $listname");
updateMaillistFiles($listname);
exit 0;

sub printUsage {
   print "Usage: mlupdate <-t> list-name\n";
   print "       Update the cached maillist info files for the maillist\n";
   print "       named \"list-name\".";
   print "       -t  Trace. Prints lots of debugging info.\n";
   print "\n";
   print "       mlupdate -a \n";
   print "       -a  Update the cached maillist info for all maillists\n";
   print "           with stale local info.\n";
   print "\n";
   print "       mlupdate -h \n";
   print "       -h  Print this usage document.\n";
   print "\n";
}

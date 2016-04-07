#! /usr/local/bin/perl
#
# getpw.pl <machine_name>: A program to extract 'passwd' file information
#	    from Sybase and use it to build a set of NIS password maps.
#
# Changes
# -------
#	Don't build passwd entries for disabled accounts.	94/11/18 RAU
#	Make script work on both catacomb and solaris servers. 	96/01/24 RAU
#	Point ypmaster back to seymour.sfu.ca from old-seymour. 96/08/01 RAU
#	Add checkpid subroutine and use it to check lock file.	97/04/07 RAU
#	Updated for perl5 and sybperl 2.			97/09/11 RAU
#	Updated to use Amaint.pm.				98/03/30 RAU
#       Updated for Paths.pm module.                            99/07/13 RAU
#       Only include disabled/locked accts if forward flag set. 00/03/06 RAU
#       Set a valid shell if for included disabled accounts.  2004/01/26 RAU
#       Do work quietly.                                      2006/02/14 RAU
#       Set crypt password fields to 'x'.                     2006/04/05 RAU
#		Convert to using SOAP call for pw map                 2007/09/28 RAU
#       Use Amaintr.pm module instead of SOAP                 2013/05/15 RAU
#

use Getopt::Std;
use lib '/opt/amaint/prod/lib';
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Paths;
require 'getopts.pl';

@nul = ( 'not null', 'null' );
select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

# The following variables define NIS and other locations.
$YPCLEARPROG = "$ETCDIR/ypclear";
$LOCKFILE    = "$LOCKDIR/passwd.lock";

acquire_lock($LOCKFILE);
my $cred  = new ICATCredentials('amaint.json')->credentialForName('amaint');
my $TOKEN = $cred->{'token'};

# Clean out any existing temporary YP map.
unlink "$YPDIR/passwd.byname.tmp.dir", "$YPDIR/passwd.byname.tmp.pag";
unlink "$YPDIR/passwd.byuid.tmp.dir",  "$YPDIR/passwd.byuid.tmp.pag";

# Get the passwd file information from the soap service.

my $amaintr = new Amaintr( $TOKEN, $main::TEST );
my $passwd = $amaintr->getPW();

# Open the temporary maps.
dbmopen( %PASSWDBYNAME, "$YPDIR/passwd.byname.tmp", 0600 );
dbmopen( %PASSWDBYUID,  "$YPDIR/passwd.byuid.tmp",  0600 );

$modtime = sprintf( "%010d", time );
$PASSWDBYNAME{"YP_LAST_MODIFIED"} = $modtime;
$PASSWDBYNAME{"YP_MASTER_NAME"}   = $YPMASTER;

$PASSWDBYUID{"YP_LAST_MODIFIED"} = $modtime;
$PASSWDBYUID{"YP_MASTER_NAME"}   = $YPMASTER;

my $count = 0;
foreach $line ( split /\n/, $passwd ) {
    my ( $username, $pw, $uid, $gid, $gcos, $homedir, $shell ) = split /:/,
      $line;
    print "$username:$pw:$uid:$gid:$gcos:$homedir:$shell\n" if $main::TEST;
    $PASSWDBYNAME{$username} = "$username:$pw:$uid:$gid:$gcos:$homedir:$shell";
    $PASSWDBYUID{$uid}       = "$username:$pw:$uid:$gid:$gcos:$homedir:$shell";
    $count++;
}

dbmclose(%PASSWDBYNAME);
dbmclose(%PASSWDBYUID);

if ( $count < 49000 ) {    # Exit if below low water mark
    print STDERR
      "Passwd info has $count rows. Not updated: below low water mark.\n";
    &cleanexit;
}

&cleanexit('test run exiting') if $main::TEST;

# Move the temporary maps to their permanent places.
open( JUNK, "mv $YPDIR/passwd.byname.tmp.dir $YPDIR/passwd.byname.dir|" );
open( JUNK, "mv $YPDIR/passwd.byname.tmp.pag $YPDIR/passwd.byname.pag|" );

open( JUNK, "mv $YPDIR/passwd.byuid.tmp.dir $YPDIR/passwd.byuid.dir|" );
open( JUNK, "mv $YPDIR/passwd.byuid.tmp.pag $YPDIR/passwd.byuid.pag|" );

release_lock($LOCKFILE);

# Go reset the NIS database, don't bother returning...
exec($YPCLEARPROG ) || die "Error in getpw: could not run ypclear.\n";

0;

#
#	Local subroutines
#

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}

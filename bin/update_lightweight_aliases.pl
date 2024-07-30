#!/usr/bin/perl
#
# update_lightweight_aliases: Fetch Lightweight Aliases map and update flatfile
#
# Changes
# -------
#       2009/07/13       First version
#   Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU
#

use Getopt::Std;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Amaintr;
use LOCK;
use Utils;
use ICATCredentials;
use Paths;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

$ALIASFILE    = "$ALIASESDIR/lightweightaliases";
$TMPALIASFILE = "$ALIASFILE.new";
$LOCKFILE     = "$ALIASESDIR/lightweightaliases.lock";

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

acquire_lock($LOCKFILE);
my $cred    = new ICATCredentials('amaint.json')->credentialForName('amaint');
my $TOKEN   = $cred->{'token'};
my $amaintr = new Amaintr( $TOKEN, $main::TEST );
my $aldata  = $amaintr->lightweightMap();
if ( $aldata =~ /^err / ) {
    cleanexit($aldata);
}
unless ($aldata) {
    print STDERR "App returned empty aliases file.\n" if $main::TEST;
    cleanexit();
}
print $aldata if $main::TEST;

# Only pull in lightweight aliases that point to other SFU accounts
# - S.Hillman - Alumni retirement
open( ALIASESSRC, ">$TMPALIASFILE" )
  || die "Can't open alumnialiases source file: ${TMPALIASFILE}.\n\n";
@alaliases = split(/\n/,$aldata);
foreach $al (@alaliases) {
    print ALIASESSRC "$al\n" if ($al =~ /sfu.ca$/ && $al !~ /alumni.sfu.ca$/);
}
close ALIASESSRC;

&cleanexit('test run exiting') if $main::TEST;

my ($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,
    $size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($TMPALIASFILE);
cleanexit("$TMPALIASFILE < low water mark: $size") if $size < 2000;

open( JUNK, "mv $TMPALIASFILE $ALIASFILE|" );
close JUNK;
release_lock($LOCKFILE);
exit 0;

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}



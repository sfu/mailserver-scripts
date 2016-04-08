#! /usr/local/bin/perl
#
# getquotas.pl <machine_name>: A program to extract quota information
#	    from the amaint db and use it to build a new quota file.
#
# - Rob Urquhart, Aug 6, 1999.
#
# Changes
# -------
# Get vol from /home link, for accounts with the migrate flag set. 99/08/18
# Add sanity check for size of new quota file.                     99/08/19
# Clear fixquota flags                                             99/11/13
# Modified for Single ID - one default quota for all accounts.   2007/03/28
# Use SOAP calls instead of direct db access.                    2007/10/05 RAU
# Only add users who are in the passwd map.                      2007/10/17 RAU
#  Use Amaintr.pm module instead of SOAP                         2013/05/15 RAU
#
# TODO: Is this script still needed? If so, needs path cleanup

use Getopt::Std;
use POSIX qw(ceil);
use File::Copy;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Filesys;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

$NETAPPETC     = "/netapp-etc";
$NETAPPETC     = "/tmp" if $main::TEST;
$QUOTAFILE     = "$NETAPPETC/quotas";
$TMPQUOTAFILE  = "$QUOTAFILE.new";
$QUOTADEFAULTS = "$QUOTAFILE.default";
$QUOTAEXTRAS   = "$QUOTAFILE.extras";
$LOCKFILE      = "/opt/adm/amaintlocks/quotas.lock";
@FILESYSTEMS   = (
    '/ugrad1',   '/ugrad2',   '/staff1', '/grad1',
    '/external', '/faculty1', '/gfs1',   '/ucs1'
);
$MINCOUNT = 15000;    # Minimum size of quota file for sanity check.
my $passwd = '';
my %UID    = ();

exit(0) if lockInUse($LOCKFILE);
acquire_lock($LOCKFILE);
my $cred    = new ICATCredentials('amaint.json')->credentialForName('amaint');
my $TOKEN   = $cred->{'token'};
my $amaintr = new Amaintr( $TOKEN, $main::TEST );

# Get the users in the passwd map

while ( ( $name, $passwd, $uid ) = getpwent ) {
    $UID{$name} = $uid;
}

# Open the temporary quota file.

open( TMPQUOTAS, ">$TMPQUOTAFILE" )
  || die "Can't open quota file: ${TMPQUOTAFILE}.\n\n";

# Get the quota Information from the account maintenance database.
# First, get the default quotas for each account class.

print "Getting default quota.\n" if $main::TEST;

$main::DEFAULTQUOTA = $amaintr->defaultFileQuota();
if ( $main::DEFAULTQUOTA =~ /^err / ) {
    cleanexit($main::DEFAULTQUOTA);
}
cleanexit("defaultFileQuota returned empty value") unless $main::DEFAULTQUOTA;
print "default quota:" . $main::DEFAULTQUOTA . "\n" if $main::TEST;

# Now get the quota for each user
print "Getting quotas.\n" if $main::TEST;
my $quotas = $amaintr->getQuotaInfo();
if ( $quotas =~ /^err / ) {
    cleanexit($quotas);
}
cleanexit("getQuotaInfo returned empty value") unless $quotas;
print "Got quotas:\n" if $main::TEST;

foreach $row ( split /\n/, $quotas ) {
    ( $user, $home, $quota, $migrate ) = split /:/, $row;
    #
    # If the migrate flag is set, the physical vol in the
    # db is incorrect. Check the /home link instead.
    #
    if ($migrate) {
        $home = get_current_vol($user);
    }
    $fs = get_filesys($home);
    $quotas{$user} = "$user:$fs:$quota:$home";
}

#	Build the quota file.
#	First, get the default quotas.

open( DEFAULTS, $QUOTADEFAULTS );
while (<DEFAULTS>) {
    print TMPQUOTAS;
}

#	Add the extra quotas.

open( EXTRAS, $QUOTAEXTRAS );
while (<EXTRAS>) {
    print TMPQUOTAS;
}

#	Finally, add individual quota for each user

print TMPQUOTAS "# Users\n";
foreach $user ( sort keys(%quotas) ) {
    next unless $UID{$user};
    ( $user, $fs, $quota, $home ) = split /:/, $quotas{$user};
    $quota = $main::DEFAULTQUOTA unless $quota;
    if ( isinlist( $fs, @FILESYSTEMS ) == 1 ) {
        print TMPQUOTAS "$user\tuser\@/vol" . $fs . "_64$fs\t$quota\n";
        $count++;
    }
}

close(TMPQUOTAS);
if ( $count < $MINCOUNT ) {
    print "New quota file is too small ($count lines). Not updated.\n";
    &cleanexit;
}

&cleanexit if $main::TEST;

# Move the temporary quota file to the quota file.

copy( $QUOTAFILE,    "$QUOTAFILE.bak" ) || die "Couldn't back up $QUOTAFILE\n";
copy( $TMPQUOTAFILE, $QUOTAFILE )       || die "Couldn't copy new quota file\n";

# Update the quotas

foreach $fs (@FILESYSTEMS) {
    $fs = substr $fs, 1;
    $fs .= "_64";
    # @out = `/usr/bin/rsh sphinx.nfs.sfu.ca \"quota resize $fs\" 2>&1`;
    # $count = grep /not updated/, @out;
    # if ( $count > 0 ) {
    #    print @out;
    # }
}

release_lock($LOCKFILE);
exit 0;

#
#	Local subroutines
#

sub isinlist {
    my ( $item, @list ) = @_;
    my $listitem = "";
    for $listitem (@list) {
        if ( $item eq $listitem ) { return 1; }
    }
    return 0;
}

sub cleanexit {
    my $msg = shift;
    release_lock($LOCKFILE);
    print STDERR $msg;
    exit 1;
}

sub EXITHANDLER {
    system 'stty', 'echo';
    print "\n\nAborted.";
    &cleanexit;
}


#! /usr/local/bin/perl
#
# migratedirs.pl <-t>: A program to move home dirs from one volume to
#	    another. Specify -t option for testing.
#
# Changes
# -------
# Use SOAP calls instead of direct db access.      2007/10/04 RAU
# Use Amaintr instead of SOAP .                    2013/05/22 RAU

use Getopt::Std;
use File::Copy;
use lib '/opt/amaint/prod/lib';
use Paths;
use Amaintr;
use Utils;
use ICATCredentials;
use Filesys;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('tv') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

my $cred = new ICATCredentials('amaint.json')->credentialForName('amaint');
$main::TOKEN = $cred->{'token'};

# Get the passwd file information from the account maintenance database.

$main::amaintr = new Amaintr( $main::TOKEN, $main::TEST );
my $rows = $main::amaintr->getAccountMigrateInfo();
if ( $rows =~ /^err / ) {
    cleanexit($rows);
}

foreach $entry ( split /\n/, $rows ) {
    my ( $username, $physhome, $uid, $gid ) = split /:/, $entry;
    print "$username $physhome $uid $gid\n" if $main::TEST;
    if ( migrateaccount( $username, $physhome, $uid, $gid ) ) {
        my $res = $main::amaintr->unsetMigrateFlag($username);
        print "Error unsetting migrate flag for $username:$res\n"
          unless $res =~ /^ok/;
    }
}

exit 0 if $main::TEST;

# Update the quota file

@out = `/opt/amaint/prod/bin/getquotas.pl`;
$count = grep /not updated/, @out;
if ( $count > 0 ) {
    print @out;
}
exit 0;

#
#	Local subroutines
#

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    exit 1;
}

sub EXITHANDLER {
    system 'stty', 'echo';
    &cleanexit("Got signal. \n\nAborted");
}

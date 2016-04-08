#!/usr/local/bin/perl
#
# process_accounts.pl: Perform expire/destroy/delete processing on accounts.
#
#  Synopsis:
#              process_accounts.pl [-xytv]
#               x         - perform expire processing
#               y         - perform destroy processing
#               t         - run in test mode
#               v         - verbose logging
#
#  Input:
#              Rows from the logins table.
#
#  Processing:
#              Does admin_override timeout processing for the logins table.
#              If expire processing is to be done:
#                  Process expire_date timeouts.
#              If destroy processing is to be done:
#                  Process destroy_date timeouts.
#
#  Output:
#              Updated rows in the logins table.
#
#  Instructions:
#              Run Mon-Thurs AM.
#
#              This program can be interrupted and restarted at any time,
#              but some information may not get printed to the log.
# Changes
# -------
#
# Keep track of processed accounts and wake up udd (on seymour) on every
# 100th change. This will prevent udd getting swamped with changes. 2002/04/25
#
# Only expire 250 active accounts at a time, to reduce the impact of large
# blocks of accounts getting expired. The scheduled runs are changed from
# once a week to 4 times a week to offset.  2003/10/10
#
# udd now runs on gun.sfu.ca.  2004/03/04
#
# Single ID changes.  2007/04/18
#
# Use SOAP calls instead of XML-RPC and direct db access.   2007/10/12  RAU
#
# Removed MAXDESTROYS and MAXEXPIRES constants. These numbers are now controlled
# from Amaint. The value is taken from the special_values table. 2010/09/02 RAU
#
# Use Amaintr.pm module instead of SOAP                     2013/05/15 RAU
#
# TODO: Move logfile path into Paths.pm

use Getopt::Std;
use POSIX qw(strftime);
use IO::Socket;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Filesys;

$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

#
#       Global variables here.
#

use constant CLASS_EMPLOYEE => 'F';
use constant CLASS_STUDENT  => 'G';
use constant CLASS_EXTERNAL => 'X';
use constant CLASS_OTHER    => 'O';

getopts('xytv') or die("Bad options");
$main::TEST    = $opt_t ? $opt_t : 0;
$main::VERBOSE = $opt_v ? $opt_v : 0;
$main::EXPIRE  = $opt_x ? $opt_x : 0;
$main::DESTRY  = $opt_y ? $opt_y : 0;

if ($main::TEST) {
    open LOG, ">&STDOUT" or die "Can't dup stdout";
}
select(STDOUT);
$| = 1;    # make unbuffered

my $cred = new ICATCredentials('amaint.json', $CREDDIR)->credentialForName('amaint');
$main::UDDHOST = $cred->{'udd_host'};
$main::UDDPORT = $cred->{'udd_port'};
$main::TOKEN   = $cred->{'token'};
$main::amaintr = new Amaintr( $main::TOKEN, $main::TEST );

$expire_count  = 0;
$destroy_count = 0;
if ($main::EXPIRE) {
    timeout_account_overrides();
    $expire_count = expire_accounts();
}
$destroy_count = destroy_accounts() if $main::DESTRY;
# &_wakeUdd if $expire_count > 0;
_log("$expire_count accounts expired.");
_log("$destroy_count accounts destroyed.");

exit 0;

#
#       Local subroutines
#

sub print_usage {
    _stderr("Usage: process_accounts.pl [-xytv]");
    _stderr("x  perform expire processing.");
    _stderr("y  perform destroy processing.");
    _stderr("t  run in test mode.");
    _stderr("v  verbose logging.");
}

sub timeout_account_overrides {
    _log("Processing override timeouts") if $main::VERBOSE;
    $result = $main::amaintr->timeoutAccountOverrides();
    if ( $result =~ /^err / ) {
        cleanexit($result);
    }
}

sub expire_accounts {
    my $count         = 0;
    my $activeCounter = 0;
    my $user          = "";
    my @users         = ();

    # Expire 'defined' accounts

    _log("Expiring 'defined' accounts.");
    foreach $user ( getExpireList("defined") ) {
        $count += expire_account( $user, 0 );
        &_incrementProcessedCount;
    }

    # Expire 'locked'accounts

    foreach $user ( getExpireList("locked") ) {
        $count += expire_account( $user, 1 );
        &_incrementProcessedCount;
    }

    # Expire 'active' accounts

    _log("Expiring 'active' accounts.");
    foreach $user ( getExpireList("active") ) {
        $activeCounter++;
        $count += expire_account( $user, 1 );
        &_incrementProcessedCount;
        sleep 20;    # sleep for 20 secs to give the home dir deletion
                     # process time to run; otherwise amaint will
                     # quickly create a couple of hundred processes.
    }
    return $count;
}

sub destroy_accounts {
    my $count = 0;
    my $user  = 0;
    my @users = ();

    _log("Destroying accounts") if $VERBOSE;

    _log("Calling flagAccountsToBeDestroyed") if $VERBOSE;
    my $result = $main::amaintr->flagAccountsToBeDestroyed();
    if ( $result =~ /^err / ) {
        cleanexit($result);
    }
    my @usernames = split /\n/, $result;
    _log("Returned from flagAccountsToBeDestroyed") if $VERBOSE;
    foreach $user (@usernames) {
        $count += destroy_account( xtrim($user) );
        &_incrementProcessedCount;
    }
    return $count;
}

#
# Destroy an account
#
sub destroy_account {
    my $user = shift;

    _log("  cleaning up $user") if $main::VERBOSE;
    delete_account_files($user) unless $main::TEST;

    #delete_archive_files( $user ) unless $main::TEST;
    my $result = $main::amaintr->destroyAccount($user);
    if ( $result =~ /^ok/ ) {
        _log("$user destroyed.") if $main::VERBOSE;
        return 1;
    }
    else {
        _stderr("Error destroying $user.");
        return 0;
    }
}

# Expire an account
#
# If ~account/.forward exists:
#       Set forward flag.
# Do db expire processing for account.

sub expire_account {
    my ( $user, $checkForward ) = @_;
    my $forward = 0;
    my $homedir = "";

    if ( $checkForward == 1 ) {
        $homedir = get_current_vol($user);
        if ( $homedir eq "" ) {
            _stderr("Couldn't get home dir for $user");
        }
        else {
            if ( -e "$homedir/.forward" ) { $forward = 1; }
        }
    }
    else {
        $forward = 0;
    }

    _log("Expiring $user") if $VERBOSE;
    return 1 if $main::TEST;
    my $result = $main::amaintr->expireAccount($user);
    if ( $result =~ /^ok/ ) {
        _log("$user expired.") if $main::VERBOSE;
        return 1;
    }
    else {
        _log( "Error expiring $user: " + $result ) if $main::VERBOSE;
        _stderr( "Error expiring $user: " + $result );
        return 0;
    }
}

sub getExpireList {
    my ($status) = @_;

    unless ($status) {
        _log("missing status arg");
        return ();
    }

    $result = $main::amaintr->getExpireList($status);
    if ( $result =~ /^err / ) {
        cleanexit($result);
    }

    return split /\n/, $result;
}

sub _incrementProcessedCount {
    $processedCount++;
# No need to wake UDD anymore as it's not used for much
# And since Rob didn't define the UDDHOST/PORT in the credentials file
# the call was failing and causing us to exit. - S.Hillman 2016/02/26
#    if ( $processedCount % 100 == 0 ) {
#        &_wakeUdd unless $main::TEST;
#        sleep 30  unless $main::TEST;
#    }
}

sub _wakeUdd {
    return if $main::TEST;

    my $socket = IO::Socket::INET->new(
        PeerAddr => $main::UDDHOST,
        PeerPort => $main::UDDPORT,
        Proto    => "tcp",
        Type     => SOCK_STREAM
      )
      or cleanexit(
        "Couldn't connect to udd on ${main::UDDHOST}/${main::UDDPORT}: $@\n");
    close $socket;

}

sub _log {
    my ($line) = @_;

    unless ( fileno LOG ) {
        open LOG, ">/opt/amaint/etc/logs/process_accounts." . time
          or die "Couldn't open log file.\n";
    }

    print LOG scalar localtime() . " $line\n";
}

sub cleanexit {
    my $msg = shift;
    print LOG "$msg\n";
    print LOG "$expire_count accounts expired.\n";
    print LOG "$destroy_count accounts destroyed.\n";
    exit 1;
}

sub EXITHANDLER {
    system 'stty', 'echo';
    cleanexit("EXITHANDLER run aborted");
}


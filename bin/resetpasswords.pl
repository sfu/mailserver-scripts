#!/usr/bin/perl
#
# Password reset script
# This script is intended to be run once a day from cron, but can be run manually
# When invoked, it checks for the existence of a maillist named $expiredpwlist-yyyymmdd
# where yyyymmdd is today's date. If the list exists, the membership is retrieved
# and each user on the list gets their password reset

use IO::Socket::INET;
use Sys::Hostname;
use FindBin;
# Find our lib directory
use lib "$FindBin::Bin/../lib";
use ICATCredentials;
# Find the maillist lib directory
use lib "$FindBin::Bin/../maillist/lib";
use MLRestClient;

use IO::Socket::SSL qw(SSL_VERIFY_NONE);
# Don't check validity of server cert - it's going to fail)
IO::Socket::SSL::set_defaults(SSL_verify_mode => SSL_VERIFY_NONE);

use LWP::UserAgent;

sub _log;

$me = `whoami`;
if ($me !~ /amaint/)
{
    die "You must be user 'amaint' to run this script";
}

$hostname = hostname();
if ($hostname =~ /stage/)
{
    # Running on a Staging host. Run in test mode
    print "Running on a Staging host. Running in Test mode\n";
    $testing=1;
}

$LOGFILE = "/tmp/resetpasswords.log";
$expiredpwlist = "its-expired-passwords-";

$cred = new ICATCredentials('maillist.json')->credentialForName('maillist');
$amtoken = $cred->{token};
die "token not found in credentials file" if (!defined($amtoken));

if (!(open(LOG,">>$LOGFILE")))
{
    print STDERR "Failed to open $LOGFILE: $@";
    open(LOG,">>/dev/null");
}
else
{
    # Make sure STDOUT and log file are unbuffered
    $| = 1;
    $old_fh = select(LOG);
    $| = 1;
    select($old_fh);
}

$today = `date +%Y%m%d`;
chomp $today;

$members = members_of_maillist($expiredpwlist.$today);

if (!scalar(@{$members}))
{
    _log "No users found to reset for $today\n";
    close LOG;
	exit 0;
}

foreach $u (sort (@{$members}))
{
	_log "Resetting $u: ";

    $cmd = "curl -ksS --noproxy sfu.ca  \"https://amaint.sfu.ca/cgi-bin/WebObjects/Amaint.woa/wa/resetCompromisedPassword?token=$amtoken&username=$u&admin=amaint&comment=Feb%202020%20Breach.%20Password%20reset\"";
    $res = `$cmd`;

    if ($res !~ /ok/)
    {
    	_log "ERROR for $u: $res\n";
    }
    else
    {
    	_log "Processed $u: success\n";
    }
}

close LOG;

exit 0;


sub restClient {
    if (!defined $restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName('robert');
       $restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$main::TEST);
    }
    return $restClient;
}

sub members_of_maillist()
{
    $listname = shift;
    $memarray = [];
    eval {
        $client = restClient();
        $ml = $client->getMaillistByName($listname);
        if (defined($ml))
        {
            my @members = $ml->members();
            return undef unless @members;
            if ($ml->memberCount() != scalar @members) 
            {
                _log "ERROR: Member count returned from MLRest doesn't match maillist member count. Aborting";
                return undef;
            }
            foreach $member (@members) 
            {
                next unless defined $member;
                push @{$memarray}, $member->canonicalAddress();
            }
        }
    };
    if ($@) {
        _log "ERROR: Caught error from MLRest client. Aborting";
        return undef;
    }
    return $memarray;
}



sub _log()
{
    $msg = shift;
    $msg =~ s/\n$//;
    print LOG scalar localtime(),": ",$msg,"\n";
    print "$msg\n";
}



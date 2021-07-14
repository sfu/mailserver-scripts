#!/usr/bin/perl
#
# Password reset script
# This script is intended to be run once a day from cron, but can be run manually
# When invoked, it checks for the existence of a maillist named $expiredpwlist-yyyymmdd
# where yyyymmdd is today's date. If the list exists, the membership is retrieved
# and each user on the list gets their password reset. A message is then sent to 
# both their external email and SFU email informing them of the reset.

# If a person's last password change date was fewer than this many days ago, skip doing a reset
$maxage = 365;

use IO::Socket::INET;
use Sys::Hostname;
use XML::LibXML;
use Net::SMTP;
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

$amainthost = "amaint.sfu.ca";

sub _log;

my $userBio;

$me = `whoami`;
if ($me !~ /amaint/)
{
    die "You must be user 'amaint' to run this script";
}

$hostname = hostname();
if ($hostname =~ /test/)
{
    # Running on a Staging host. Run in test mode
    print "Running on a Staging host. Running in Test mode\n";
    $testing=1;
    $amainthost = "stage.its.sfu.ca";
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

    $userBio = get_user_bio($u);
    if (defined($userBio))
    {
        $lastChanged = $userBio->findvalue("/syncLogin/login/lastPasswordChangeDate");
        if ($lastChanged =~ /(\d\d\d\d)-(\d\d)-(\d\d)T/)
        {
            $lastChanged = "$1$2$3";
            if ($lastChanged > 20210425 && ($today-$lastChanged < $maxage))
            {
                _log "  Password for $u last changed on $lastChanged. Skipping";
                next;
            }
        }
    }

    $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/resetExpiredPassword?token=$amtoken&username=$u&admin=amaint\"";
    $res = `$cmd`;

    if ($res !~ /ok/)
    {
    	_log "ERROR for $u: $res\n";
    }
    else
    {
    	_log "Processed $u: success\n";
        send_expiry_email($u);
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

sub send_expiry_email()
{
    my $username = shift;
    my $email = "";
    my $displayName = $username;

    my $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getUserBio?token=$amtoken&username=$username\"";
    my $xmlbody = `$cmd`;
    
    if (defined($userBio))
    {
        if ($userBio->exists("/syncLogin"))
        {
            $ee = $userBio->findvalue("/syncLogin/person/externalEmail");
            $email = "$ee," if ($ee =~ /\@/);
            $displayName = $userBio->findvalue("/syncLogin/login/gcos") || $username;
        }
    }
    $email .= "$username\@sfu.ca";
    $msg = <<EOM;
From: SFU IT Service Desk <itshelp\@sfu.ca>
To: $displayName <$username\@sfu.ca>
Subject: Your SFU computing account password has been reset

The password for your SFU Computing account has expired and was automatically reset. To regain access to your account, 
you will need to use the "Forgot Password" link on the SFU CAS login page

If you have any questions about this message, please contact the SFU IT Service Desk at 778-782-8888 or itshelp\@sfu.ca
EOM
    $email = "stevehillman\@gmail.com,hillman\@sfu.ca" if ($testing);
    send_message("localhost",$msg,$email);

}

sub send_message()
{
    my ($server,$msg,$recipient) = @_;

    my $smtp = Net::SMTP->new($server);
    return undef unless $smtp;
	
	my $from = "amaint\@sfu.ca";
    my $rc = $smtp->mail($from);
    if ($rc)
    {
        foreach my $recip (split(/,/,$recipient))
        {
            $rc = $smtp->to($recip);
            last if (!$rc);
        }
        if ($rc)
        {
            $rc = $smtp->data([$msg]);
			_log("sent to $recipient");
        }
		else
		{
			_log("ERROR for $recipient. Bad address?");
		}
        $smtp->quit();
    }
    return $rc;
}

sub get_user_bio()
{
    my $username = shift;
    my $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getUserBio?token=$amtoken&username=$username\"";
    my $xmlbody = `$cmd`;
    my $xpc = undef;
    
    if ($xmlbody =~ /^err/)
    {
        _log "ERROR fetching userBio for $username.";
    }
    else
    {
        $xdom  = XML::LibXML->load_xml(
             string => $xmlbody
           );

        $xpc = XML::LibXML::XPathContext->new($xdom);
    }
    return $xpc;
}


sub _log()
{
    $msg = shift;
    $msg =~ s/\n$//;
    print LOG scalar localtime(),": ",$msg,"\n";
    print "$msg\n";
}



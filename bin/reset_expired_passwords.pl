#!/usr/bin/perl
#
# Password expiry management.
#
# This script is intended to be run once a day from cron, but can be run manually
# When invoked, it performs three tasks:
# - checks for the existence of a maillist named $expiredpwlist-yyyymmdd
#   where yyyymmdd is today's date. If the list exists, the membership is retrieved
#   and each user on the list gets their password reset. A message is then sent to 
#   both their external email and SFU email informing them of the reset.
# - Checks to see whether there's a new password-expiry maillist to create this week. Only
#   one list is created per week. If this script fails to run one night though, the list will
#   be created the next successful night.
#   A call is made to Amaint to fetch the next batch of users whose passwords are the oldest, and
#   adds them to the newly created list
# - Checks the previous week's expiry list for sponsored accounts and emails the sponsor to remind
#   them that the password will expire

# If a person's last password change date was fewer than this many days ago, skip doing a reset
$maxage = 365;

use IO::Socket::INET;
use Sys::Hostname;
use XML::LibXML;
use Net::SMTP;
use Time::Local;
use Data::Dumper;
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
$LOGFILE = "/tmp/resetpasswords.log";
$expiredpwlist = "its-expired-passwords-";

sub _log;

my $userBio;
my %expiring_members;

$me = `whoami`;
if ($me !~ /amaint/)
{
    die "You must be user 'amaint' to run this script";
}

### Setup ###
$hostname = hostname();
if ($hostname =~ /test/)
{
    # Running on a Staging host. Run in test mode
    print "Running on a Staging host. Running in Test mode\n";
    $testing=1;
    $amainthost = "stage.its.sfu.ca";
}

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


### Main processing ###

# process_expired_passwords();
find_maillists($expiredpwlist);
my $newlist = create_maillist("$expiredpwlist"."20210930","This is a test");
print Dumper($newlist);

close LOG;

exit 0;

### Done ###
# Local Subroutines below here #

# Attempt to fetch the members of a maillist whose name ends with today's date.
# If found, iterate over the members and reset all of their passwords, notifying them
# at both their SFU and external email address. If the account is a sponsored account, also
# notify the sponsor.
sub process_expired_passwords()
{
    _log "Processing expired passwords for $today";
    my $members = members_of_maillist($expiredpwlist.$today);

    if (!scalar(@{$members}))
    {
        _log "No users found to reset for $today\n";
        return;
    }

    foreach $u (sort (@{$members}))
    {
        _log "Resetting $u: ";

        my $isSponsored = 0;

        # Try to get the user's bio data (ActiveMQ message content) from Amaint
        $userBio = get_user_bio($u);
        if (defined($userBio))
        {
            my $lastChanged = $userBio->findvalue("/syncLogin/login/lastPasswordChangeDate");
            if ($lastChanged =~ /(\d\d\d\d)-(\d\d)-(\d\d)T/)
            {
                $lastChanged = "$1$2$3";
                if ($lastChanged > 20210425 && ($today-$lastChanged < $maxage))
                {
                    _log "  Password for $u last changed on $lastChanged. Skipping";
                    next;
                }
            }
            $sponsored = $userBio->findvalue("/syncLogin/person/sfuSponsoredType");
            $isSponsored = 1 if (defined($sponsored) && $sponsored ne "");
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
            send_expiry_email($u,$userBio);
            send_sponsor_expiry_email($u) if $isSponsored;
        }
    }
}

# Fetch all future pw expiry maillists and their users 
sub get_expiring_users()
{
    # First, fetch all maillists that match the pattern
    my $mlists = find_maillists($expiredpwlist);
    if (defined($mlists) && scalar(@$mlists) > 0)
    {
        # Then fetch the members of each list and save in a hash
        foreach my $ml (@$mlists)
        {
            $expiring_members{$ml->{name}} = members_of_maillist($ml->{name});
        }
    }
    else
    {
        _log "No maillists retrieved matching pattern $expiredpwlist!";
    }
}

# Add this week's expiring users to a new maillist, if necessary 
sub add_expiring_users()
{
    my $dayOfWeek = `date +%w`;
    chomp $dayOfWeek;

    # Only create the list on Tuesday, Wed, or Thurs (will normally always happen on Tuesday unless
    # the script fails for some reason)
    if ($dayOfWeek < 2 || $dayOfWeek > 4)
    {
        _log "  Too early in the week. Skipping new maillist creation";
        return;
    }

    # Calculate the date 3 weeks from today. That's the date we'll use for our new expire maillist
    my @tempDate = localtime(time() + (86400*21));
    my $createDate = ($tempDate[5] + 1900)*10000 + ($tempDate[4]+1)*100 + $tempDate[3];

    # See if a maillist already exists with a date within 3 days of our target date
    foreach my $ml (keys %expiring_members)
    {
        if ($ml =~ /-(\d+)$/)
        {
            if (date_diff($1,$createDate) < 3)
            {
                _log "  A recent expiry maillist exists: $ml. Skipping creation";
                return;
            }
        }
    }
}

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

# Find maillists by wildcard. A "*" is automatically appended to the search string provided
sub find_maillists()
{
    $listsearch = shift;
    $mlarray = [];
    my $mlists;
    eval {
        $client = restClient();
        $mlists = $client->getMaillistsByNameWildcard($listsearch);
    };
    if ($@) {
        _log "ERROR: Caught error from MLRest client. Aborting";
        return undef;
    }
    return $mlists;
}

sub create_maillist()
{
    $listname = shift;
    $desc = shift;
    my $ml;
    eval {
        $client = restClient();
        $ml = $client->createMaillist($listname,$desc);
    };
    if ($@) {
        _log "ERROR: Caught error from MLRest client. Aborting";
        return undef;
    }
    return $ml;
}

sub send_expiry_email()
{
    my ($username,$bio) = @_;
    my $email = "";
    my $displayName = $username;
    
    if (defined($bio))
    {
        if ($bio->exists("/syncLogin"))
        {
            $ee = $bio->findvalue("/syncLogin/person/externalEmail");
            $email = "$ee," if ($ee =~ /\@/);
            $displayName = $bio->findvalue("/syncLogin/login/gcos") || $username;
        }
    }
    $email .= "$username\@sfu.ca";
    $msg = <<EOM;
From: SFU IT Service Desk <itshelp\@sfu.ca>
To: $displayName <$username\@sfu.ca>
Subject: Your SFU computing account password has been reset

The password for your SFU Computing account has expired and was automatically reset. To regain access to your account, 
attempt to log in to SFU services (such as SFU Mail or goSFU) and click on the "Forgot Password" link. 
If you need any assistance, please contact the IT Service Desk.

If you have any questions about this message, please contact the SFU IT Service Desk at 778-782-8888 or itshelp\@sfu.ca

Thank you,
IT Services
Simon Fraser University | Strand Hall 1001
8888 University Dr., Burnaby, B.C. V5A 1S6
www.sfu.ca/information-systems
Twitter: \@sfu_it
EOM
    $email = "stevehillman\@gmail.com,hillman\@sfu.ca" if ($testing);
    send_message("localhost",$msg,$email);

}

sub send_sponsor_expiry_email()
{
    my $username = shift;
    my $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getSponsorForUser?token=$amtoken&username=$username\"";
    my $sponsor = `$cmd`;
    if ($sponsor ne "" && $sponsor !~ /^err/)
    {
        my $email = "$sponsor\@sfu.ca";
        my $msg = <<EOM;
From: SFU IT Service Desk <itshelp\@sfu.ca>
To: $sponsor\@sfu.ca
Subject: The password of sponsored account '$username' has been reset

You are receiving this message because our records indicate that you are the sponsor of computing account '$username'.

The password for SFU Computing account '$username' has expired and was automatically reset. If this is a personal account,
the user of the account can attempt to log in to SFU services (such as SFU Mail or goSFU) and click on the "Forgot Password" link. 

If this is a departmental role account, please contact the IT Service Desk to arrange to get the password reset

If you have any questions about this message, please contact the SFU IT Service Desk at 778-782-8888 or itshelp\@sfu.ca

Thank you,
IT Services
Simon Fraser University | Strand Hall 1001
8888 University Dr., Burnaby, B.C. V5A 1S6
www.sfu.ca/information-systems
Twitter: \@sfu_it
EOM
        $email = "stevehillman\@gmail.com,hillman\@sfu.ca" if ($testing);
        send_message("localhost",$msg,$email);
    }
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

# Fetch a user bio (ActiveMQ message) from Amaint via DirectAction call
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

# Calculate how many days apart two dates are. Dates are in the format YYYYMMDD
# If the second date is later than the first, the result will be positive. Otherwise, negative
sub date_diff()
{
    my @dates = @_;
    my @epochs;
    foreach my $d (@dates)
    {
        if ($d =~ /(\d\d\d\d)(\d\d)(\d\d)/)
        {
            push (@epochs, timelocal(0,0,0,$3,$2,$1));
        }
    }
    return (($epochs[1] - $epochs[0])/86400);
}


sub _log()
{
    $msg = shift;
    $msg =~ s/\n$//;
    print LOG scalar localtime(),": ",$msg,"\n";
    print "$msg\n";
}



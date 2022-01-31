#!/usr/bin/perl
#
# Password expiry management.
#
# This script is intended to be run once a day from cron, but can be run manually.
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

# Exclude certain date ranges. No expiry maillist will be created within these ranges.
# First number is start date (mmdd), second is end date
@excludedateranges = (
    101,114,
    401,515,
    701,701,
    801,915,
    930,930,
    1111,1111,
    1201,1231
);

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
$LOGFILE = "/tmp/process-expiring-passwords.log";
$parentpwlist = "its-expired-passwords";
$expiredpwlist = "$parentpwlist-";
$alert_recip = "amaint-system-messages\@sfu.ca";

sub _log;

my $userBio;
my %expiring_members;
my $newaccts = [];

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

# $main::VERBOSE=1;
_log "Starting up";
process_expired_passwords();  # process today's expiring passwords, if any
get_expiring_users();         # Fetch members of any future expiring password lists, for the next 3 weeks
add_expiring_users();         # Create new list and add new expiring users, if any, and if applicable (once a week)
notify_sponsors();            # For upcoming sponsored accounts, notify their sponsors, one msg per sponsor
_log "Done";
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


# Add this week's expiring users to a new maillist, if necessary.
# First, check the day of week. We only attempt to create a list on Tuesday, Wednesday, and Thursday morning
# Second, make sure the date wouldn't fall within a forbidden date range
# Last, check to see whether a list has already been created this week by
# checking the names of all of the lists fetched by get_expiring_users. We only create one list a week
#
# If no list exists yet:
#  - fetch at most 800 employee accounts and
#    -  3000 non-employee fullweight accounts and
#    -  3000 lightweight accounts (skipping these for now).
#  - if the set is non-zero, create the maillist and add the users
#
# The SQL query that Amaint uses doesn't work if we tell it to exclude people who are already on an
# expire-password list, so we need to do the work ourselves. We collect together everyone who's
# already on a list and stuff them into a hash. We also fetch 4 times as many users from Amaint as
# we need, to account for people who may be on the future password expiry lists
sub add_expiring_users()
{
    my $dayOfWeek = `date +%w`;
    chomp $dayOfWeek;

    # Only create the list on Tuesday, Wed, or Thurs (will normally always happen on Tuesday unless
    # the script fails for some reason)
    if ($dayOfWeek < 2 || $dayOfWeek > 4)
    {
        _log "  Too early or late in the week. Skipping new maillist creation";
        return;
    }

    # Calculate the date 3 weeks from today. That's the date we'll use for our new expire maillist
    my @tempDate = localtime(time() + (86400*21));
    $createDate = ($tempDate[5] + 1900)*10000 + ($tempDate[4]+1)*100 + $tempDate[3];

    # Check to see whether the expiry date would fall within an excluded date range
    my $rangecheck = ($tempDate[4]+1)*100 + $tempDate[3];
    my $i = 0;
    for (my $i=0; i < scalar(@excludedateranges); $i += 2)
    {
        if ($rangecheck >= $excludedateranges[$i] && $rangecheck <= $excludedateranges[$i+1])
        {
            _log "  Maillist date would fall within excluded range " . 
                $excludedateranges[$i] . " and " . $excludedateranges[$i+1] .". Skipping creation";
            return;
        }
    }

    # See if a maillist already exists with a date within 3 days of our target date
    # Also save the membership of every future list in a hash
    my %future_expiring;
    foreach my $ml (keys %expiring_members)
    {
        if ($ml =~ /-(\d+)$/)
        {
            my $datediff = date_diff($1,$createDate);
            if ($datediff < 3)
            {
                _log "  Target date: $createDate. A recent expiry maillist exists: $ml. Skipping creation";
                return;
            }
            if ($datediff > -1)
            {
                # List is today or in the future. Save its members
                foreach my $mem (@{$expiring_members{$ml}})
                {
                    $future_expiring{$mem} = 1;
                }
            }
            
        }
    }

    my @staff,@nonstaff,@lwaccts;

    _log "Fetching list of users to add to expiring passwords list";

    my $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getExpiringPasswords?token=$amtoken&days=$maxage&employees=1&size=1600\"";
    my $staffresp = `$cmd`;
    if ($? || $staffresp =~ /^err -/)
    {
        _log "Amaint error: $staffresp. Skipping creation of new maillist";
        return;
    }
    
    my $counter = 0;
    foreach my $m1 (split(/\n/,$staffresp))
    {
        if (!defined($future_expiring{$m1}))
        {
            push @staff,$m1;
            $counter++;
            last if ($counter >= 400);
        }
    }

    $cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getExpiringPasswords?token=$amtoken&days=$maxage&employees=0&size=6400\"";
    my $nonstaffresp = `$cmd`;
    if ($? || $nonstaffresp =~ /^err -/)
    {
        _log "Amaint error for non-staff: $nonstaffresp.";
    }
    else
    {
        $counter = 0;
        foreach my $m2 (split(/\n/,$nonstaffresp))
        {
            if (!defined($future_expiring{$m2}))
            {
                push @nonstaff,$m2;
                $counter++;
                last if ($counter >= 1600);
            }
        }
    }

    # For now, skip lightweight accounts - we may just disable lw accounts
    # that haven't changed their password since we last reset them

    #$cmd = "curl -ksS --noproxy sfu.ca  \"https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getExpiringPasswords?token=$amtoken&days=$maxage&lightweight=1&ExcludeMlMembers=1&size=3000\"";
    #my $lwresp = `$cmd`;
    #if ($? || $lwresp =~ /^err -/)
    #{
    #    _log "Amaint error for lightweights: $lwresp.";
    #}
    #else
    #{
    #    @lwaccts = split(/\n/,$lwresp);
    #}

    push(@$newaccts,@staff,@nonstaff,@lwaccts);

    if (scalar(@$newaccts) == 0)
    {
        _log "No expiring passwords found. Skipping maillist creation";
        return;
    }

    my $ml = create_maillist($expiredpwlist.$createDate,"Users whose passwords expire on $createDate");
    if (!defined($ml))
    {
        _log "Maillist creation failed!";
        send_alert("Creation of $expiredpwlist$createDate failed! Check logs for details");
        $newaccts = [];
        return;
    }
    else
    {
        _log "Created new maillist $expiredpwlist$createDate";
    }

    _log "  Adding ".scalar(@$newaccts)." users to maillist";

    my $res = replace_members_of_maillist($expiredpwlist.$createDate,$newaccts);
    if (!defined($res))
    {
        # The member-add will almost certainly appear to fail, as it'll usually take longer than the NSX LB
        # is willing to wait. So sleep for a bit, then grab the membership from AOBRest and see what
        # we have
        _log "Got a failure response from adding members. Sleeping and trying to retrieve members from MLRest";
        sleep 240;
        $newmembers = members_of_maillist($expiredpwlist.$createDate);
        if (!scalar(@$newmembers))
        {
            _log "Failed to add members to maillist $expiredpwlist$createDate!";
            send_alert("Adding members to $expiredpwlist$createDate failed! Check logs for details. Delete the maillist to have the script try again tonight.");
            $newaccts = [];
            return;
        }
        elsif (scalar(@$newmembers) < scalar(@$newaccts))
        {
            _log "Warning: Not all users were added. List has ".scalar(@$newmembers)." users instead of ".scalar(@$newaccts);
            send_alert("Warning: Some users failed to be added to $expiredpwlist$createDate. Expected ".scalar(@$newaccts)." but got ".scalar(@$newmembers));
            # Just track the users that got added
            $newaccts = $newmembers;
        }
    }

    _log "  Added ". scalar(@staff)." staff, ". scalar(@nonstaff)." non-staff, and ".scalar(@lwaccts)." lightweight accounts to new maillist.";
    
    return if ($testing);

    # Add new maillist to the parent list
    $res = add_member_to_maillist($parentpwlist,$expiredpwlist.$createDate);
    if (!defined($res))
    {
        _log "Failed to add maillist $expiredpwlist$createDate to parent list $parentpwlist";
        send_alert("Adding $expiredpwlist$createDate to $parentpwlist failed! Check logs for details. Manually add the list to the parent list to ensure users get the Nag screen.");
        return;
    }
}

# Notify Sponsors
# This function notifies all sponsors about upcoming password expiration
# of accounts they sponsor. The notice will include all accounts they sponsor,
# and will include notifications for both 1 week out and 3 weeks out 
sub notify_sponsors()
{        
    my %sponsors,$sp;

    # First, find the expiry maillist for 1 week out
    my $oneweekml;
    my @oneweeklist;
    foreach my $ml (keys %expiring_members)
    {
        if ($ml =~ /-(\d+)$/)
        {
            if (date_diff($today,$1) == 7)
            {
                $oneweekml = $ml;
                last;
            }
        }        
    }

    # Iterate over it and find every sponsored account
    foreach my $acct (@{$expiring_members{$oneweekml}})
    {
        $sp = get_sponsor($acct);
        if ($sp)
        {
            if (!defined($sponsors{$sp}))
            {
                $sponsors{$sp} = {
                    oneweek => [$acct],
                    new => []
                };
            }
            else
            {
                push (@{$sponsors{$sp}->{oneweek}},$acct);
            }
        }
    }

    # if there are any new accounts added today, iterate over them to identify sponsors
    # and add them to the existing list
    if (scalar(@$newaccts))
    {
        foreach my $acct (@$newaccts)
        {
            $sp = get_sponsor($acct);
            if ($sp)
            {
                if (!defined($sponsors{$sp}))
                {
                    $sponsors{$sp} = {
                        oneweek => [],
                        new => [$acct]
                    };
                }
                else
                {
                    push (@{$sponsors{$sp}->{new}},$acct);
                }
            }
        }
    }

    # Calculate our dates
    my $oneweekdate,$threeweekdate;
    if ($oneweekml =~ /-(\d\d\d\d)(\d\d)(\d\d)$/)
    {
        $oneweekdate = "$1-$2-$3";
    }
    if ($createDate =~ /(\d\d\d\d)(\d\d)(\d\d)$/)
    {
        $threeweekdate = "$1-$2-$3";
    }


    # We have our hash of sponsors. Each key (sponsor account) contains a hash with two keys
    #  - an array of sponsored accounts expiring in a week
    #  - an array of sponsored accounts expiring in 3 weeks
    # Send a single email to each sponsor with a list of all accounts and their password expiry date
    foreach my $sp (keys %sponsors)
    {
        my $msg = <<EOM2;
From: SFU IT Service Desk <itshelp\@sfu.ca>
To: $sp\@sfu.ca
Subject: Passwords will expire on one or more of your sponsored accounts

You are receiving this message because our records indicate that you are the sponsor of one or more sponsored SFU Computing IDs
whose passwords will expire soon.

EOM2
        if (scalar(@{$sponsors{$sp}->{oneweek}}))
        {
            $msg .= "Passwords for the following accounts will expire in ONE WEEK, at 1:00am on $oneweekdate:\n---------------\n";
            foreach my $u (@{$sponsors{$sp}->{oneweek}})
            {
                $msg .= "$u\n";
            }
            $msg .= "\n";
        }

        if (scalar(@{$sponsors{$sp}->{new}}))
        {
            $msg .= "Passwords for the following accounts will expire in 3 weeks, at 1:00am on $threeweekdate:\n---------------\n";
            foreach my $u (@{$sponsors{$sp}->{new}})
            {
                $msg .= "$u\n";
            }
            $msg .= "\n";
        }

        
        $msg .= <<EOM3;

To change the password for a sponsored account, someone who knows the current password can visit https://my.sfu.ca and
login with the current account's password, click on the 'Change Password' tab, and choose a new password.

If you have any questions about this message, please contact the SFU IT Service Desk at 778-782-8888 or itshelp\@sfu.ca

Thank you,
IT Services
Simon Fraser University | Strand Hall 1001
8888 University Dr., Burnaby, B.C. V5A 1S6
www.sfu.ca/information-systems
Twitter: \@sfu_it
EOM3
        my $email = "$sp\@sfu.ca";
        $email = "stevehillman\@gmail.com,hillman\@sfu.ca" if ($testing);
        send_message("127.0.0.1",$msg,$email);
        _log "  Sent sponsor warning email to $sp for one week accts: ".join(",",@{$sponsors{$sp}->{oneweek}})." and three week accts: ".join(",",@{$sponsors{$sp}->{new}});
    }
}



# Fetch all future pw expiry maillists and their users 
# We use this list to notify sponsors closer to the expiry date of sponsored accounts
sub get_expiring_users()
{
    # First, fetch all maillists that match the pattern
    my $mlists = find_maillists($expiredpwlist);
    my $count=0;
    if (defined($mlists) && scalar(@$mlists) > 0)
    {
        # Then fetch the members of each list and save in a hash
        foreach my $ml (@$mlists)
        {
            $expiring_members{$ml->{name}} = members_of_maillist($ml->{name});
            $count += scalar(@{$expiring_members{$ml->{name}}});
        }
        _log "Retrieved ".scalar(keys %expiring_members)." maillists with a total of $count users.";
    }
    else
    {
        _log "No maillists retrieved matching pattern $expiredpwlist!";
    }
}

sub restClient {
    if (!defined $restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName(($testing) ? 'testing' : 'robert');
       $restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$testing);
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

# Create a password expiry maillist. This function could also be used for
# other lists, but you may want to adjust the attributes that get set on the list
# after creation
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

    # Set our desired attributes on the list
    $res = $client->modifyMaillist($ml, {
        owner => "amaint",
        disableUnsubscribe => "true",
        defaultDeliver => "false",
        hidden => "true",
        localDefaultAllowedToSend => "true"
    });
    return $ml;
}

# Replace all members of a maillist with the members in the passed in array reference.
sub replace_members_of_maillist()
{
    my ($listname,$members) = @_;
    my $result;
    eval {
        $client = restClient();
        $result = $client->getMaillistByName($listname);
        $result = $client->replaceMembers($result,$members);
    };

    if ($@) {
        _log "ERROR: Caught error from MLRest client. Aborting. $@";
        return undef;
    }
    return $result;

}

# Add a single member to a maillist
sub add_member_to_maillist()
{
    my ($listname,$member) = @_;
    my $result;
    eval {
        $client = restClient();
        $result = $client->getMaillistByName($parentpwlist);
        $result = $client->addMember($result,$member);
    };

    if ($@) {
        _log "ERROR: Caught error from MLRest client. Aborting. $@";
    }

    return $result;
}

# After an account's password has been reset for not changing their password in time
# send the end-user a notification. Send it to both their SFU and external email address.
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
Subject: Your SFU computing ID password has been reset

The password for your SFU Computing ID has expired and was automatically reset. To regain access to your account, 
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
    send_message("127.0.0.1",$msg,$email);

}

sub send_sponsor_expiry_email()
{
    my $username = shift;
    my $url = "https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getSponsorForUser?token=$amtoken&username=$username";
    my $sponsor;
    eval {
        $sponsor = MLRestClient::_httpGet($url,1);
    };
    if (defined($sponsor) && $sponsor ne "" && $sponsor !~ /^err/)
    {
        my $email = "$sponsor\@sfu.ca";
        my $msg = <<EOM;
From: SFU IT Service Desk <itshelp\@sfu.ca>
To: $sponsor\@sfu.ca
Subject: The password of sponsored account '$username' has been reset

You are receiving this message because our records indicate that you are the sponsor of computing account '$username'.

The password for SFU Computing ID '$username' has expired and was automatically reset. If this is a personal account,
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
        send_message("127.0.0.1",$msg,$email);
    }
}

sub send_message
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

sub send_alert()
{
    my $alert = shift;

    my $msg = <<EOF2;
From: Account Maintenance <amaint\@sfu.ca>
To: $alert_recip
Subject: Alert from process-password-expiry script on $hostname server

An error occurred while processing password expiry:

$alert

Logfile is at $LOGFILE on $hostname

EOF2
    send_message("127.0.0.1",$msg,$alert_recip);
}

# Fetch a user bio (ActiveMQ message) from Amaint via DirectAction call
sub get_user_bio()
{
    my $username = shift;
    my $url = "https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getUserBio?token=$amtoken&username=$username";
    my $xmlbody;
    eval {
        $xmlbody = MLRestClient::_httpGet($url,1);
    }; 
    my $xpc = undef;
    
    if (!defined($xmlbody) || $xmlbody =~ /^err/)
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

# Get the sponsor of an account, if any
sub get_sponsor
{
    my $username = shift;
    my $url = "https://$amainthost/cgi-bin/WebObjects/Amaint.woa/wa/getSponsorForUser?token=$amtoken&username=$username";
    my $sponsor;
    eval {
        $sponsor = MLRestClient::_httpGet($url,1);
    };
    if (!defined($sponsor) && $main::HTTPCODE != 404)
    {
        _log "Error getting sponsor for $username";
    }
    return $sponsor;
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



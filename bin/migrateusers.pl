#!/usr/bin/perl
#
# Exchange Migration script
# This script is intended to be run once a day from cron, but can be run manually
# When invoked, it checks for the existence of a maillist named $maillistroot-yyyymmdd
# where yyyymmdd is today's date. If the list exists, the membership is retrieved
# and each user on the list is migrated from Zimbra to Exchange by following these
# steps:
#
#  1. Call Exchange Daemon to enable the user's mailbox
#  2. modify mailgw1's Aliases map to point at Exchange
#  3. add user to manualexchangeusers file on mailgw1
#  3. call daemon on mailgw2 to repeat above 2 steps there
#  5. ssh to jaguar7 and execute zmprov command to disable mailbox for user on Zimbra
#
# Once all users are processed, add all successful ones to emailpilot-users list
# Email final result to exchange-admins

use IO::Socket::INET;
use Sys::Hostname;
use DB_File;
use Net::SMTP;
use FindBin;
# Find our lib directory
use lib "$FindBin::Bin/../lib";
use ICATCredentials;
# Find the maillist lib directory
use lib "$FindBin::Bin/../maillist/lib";
use MLRestClient;

$hostname = hostname();
if ($hostname =~ /stage/)
{
    # Running on a Staging host. Run in test mode
    print "Running on a Staging host. Running in Test mode\n";
    $testing=1;
}

$maillistroot = "exchange-migrations-";
$lastemailfile = "/home/hillman/sec_html/mail/lastmsg";
$firstemailfile = "/home/hillman/sec_html/mail/firstmsg";

$migratedlist = "emailpilot-users";
$targetserver = "mailgw2.tier2.sfu.ca";
$zimbraserver = "jaguar7.tier2.sfu.ca";
$zimbramailserver = "connect.sfu.ca";

if ($testing)
{
    $migratedlist = "lcp-test";
    $targetserver = "localhost";
    $zimbraserver = "alpha.tier2.sfu.ca";
    $zimbramailserver = "email-stage.sfu.ca";
}


my $cred  = new ICATCredentials('exchange.json')->credentialForName('daemon');
my $TOKEN = $cred->{'token'};
$SERVER = $cred->{'server'};
$EXCHANGE_PORT = $cred->{'port'};
$DOMAIN = $cred->{'domain'};
$RESTTOKEN = $cred->{'resttoken'};


if (defined($ARGV[0]))
{
    $member = $ARGV[0];
    print "Specified user '$member' on command line. Just processing that user\n";
    $members = [$member];
}
else
{
    $today = `date +%Y%m%d`;
    chomp $today;
    $members = members_of_maillist($maillistroot.$today);
}


if (!$members)
{
	print "No users found to migrate for $today\n";
	exit 0;
}

# We can live with these commands failing, so don't worry about return codes
unlink("/opt/mail/manualexchangeusers");
process_q_cmd($targetserver,"6083","clearman");

foreach $u (@{$members})
{
	print "Processing $u: ";
    $resource = 0;
    $user = $u;
    if ($user =~ /\@resource.sfu.ca/)
    {
        $resource = 1;
        $user =~ s/\@.*//;
    }
	$res = process_q_cmd($SERVER, $EXCHANGE_PORT, "$TOKEN enableuser $user");
	if ($res !~ /^ok/)
	{
        # Failed to enable Exchange account. We can't proceed further for this user
		print $res;
		next if (!$testing);
        print "Test mode so continuing anyway\n";
	}

	$fail=0;

    # Exchange done, add user to Aliases on mail servers
    # We'll do the remote server first, as there's much less chance of a local failure
    $resp = process_q_cmd($targetserver,"6083","adduser $user");
    if ($resp !~ /^ok/)
    {
        $fail |= 4;
        $res = "Error talking to mailgw2. "
    }
    
    if (!$fail)
    {
        if (open(MEU,">>/opt/mail/manualexchangeusers"))
        {
        	print MEU "$user: $user\@$DOMAIN\n";
        	close MEU;
        }
        else
        {
        	$fail = 2;
        	$res = "Failed to open manualexchangeusers for writing. ";
        }
    }
    if (!$fail)
    {
    	# Open the Aliases map.
    	if (tie( %ALIASES, "DB_File","/opt/mail/aliases2.db", O_CREAT|O_RDWR,0644,$DB_HASH ))
      	{
            if ($ALIASES{"$user\0"} eq "$user\@$DOMAIN\0")
            {
                $fail |=1 ;
                $res .= "User already migrated.";
            }
            else
            {
    		    $ALIASES{"$user\0"} = "$user\@$DOMAIN\0";
            }
    		untie (%ALIASES);
    	}
    	else
    	{
    		$fail |= 1;
    		$res .= "Failed to open aliases2 database for updating";
            # We can actually ignore this error because the flat file got updated, so next time aliases are rebuilt, they'll pick up the change
    	}
    }    

    if ($fail > 1)
    {
        # Non-ignorable error happened - back out of Exchange account enable
        $resp = process_q_cmd($SERVER, $EXCHANGE_PORT, "$TOKEN disableuser $user");
        $res .= $resp;
        if ($fail < 4)
        {
            # Change to mailgw2 succeeded. We need to back that out
            $resp = process_q_cmd($targetserver,"6083","undo $user");
        }
    }

    $recip = $testing ? "hillman" : "$user";

    if (!$fail)
    {
        # Send user their last msg to Zimbra
        $rc = send_message($zimbramailserver,$lastemailfile,$recip) if (!$resource);
        sleep 1;
        $cmd = "ssh zimbra\@$zimbraserver zmprov ma $user zimbraMailStatus disabled";
    	system($cmd);
        if ($? != 0)
        {
            # We had a problem
            $fail = 4;
            $rc = $? >> 8;
            $res = "ssh to Zimbra had rc=$rc."
        }
        send_message("localhost",$firstemailfile,$recip) if (!$resource && ($testing || !$fail));
    }

    if ($fail)
    {
    	print $res,"\n";
        if ($testing)
        {
            print "$user failed, but running in testing mode, so marking as successful\n";
            push @usersdone,$user;
        }
    }
    else
    {
    	print "success\n";
    	push @usersdone,$u;
    }
}

if (!scalar(@usersdone))
{
    print "No users successfully processed. Exiting\n";
    exit 0;
}

# Rob sprinkled his Maillist client library with 'die's and 'exit's, so wrap in eval statements
eval {
    $client = restClient();
    $ml = $client->getMaillistByName($migratedlist) if (defined($client))
};

foreach $user (@usersdone)
{
    $mem=0;
    if (defined($client) && defined($ml))
    {
        eval {
            $mem = $client->addMember($ml,$user)
        };
    }
    if (!$mem)
    {
        # Something went wrong, user didn't add
        push @failed,$user;
    }
}

if (scalar(@failed))
{
    print "Error updating $migratedlist. The folowing users were migrated but not added to the list.\n";
    print "They must be manually added before another migration is run\n";

    foreach $user (@failed)
    {
        print $user,"\n";
    } 
}

exit 0;

sub process_q_cmd()
{
	my ($server,$port,$cmd) = @_;
	my $sock = IO::Socket::INET->new("$server:$port");
	if ($sock)
	{
		$junk = <$sock>;	# wait for "ok" prompt
		print $sock "$cmd\n";
		@res = <$sock>;
		close $sock;
	}
	else
	{
		@res = ["err Connection error: $@"];
	}

	return join("",@res);
}

sub restClient {
    if (!defined $restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName('robert');
       $restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$main::TEST);
    }
    return $restClient;
}

sub send_message()
{
    my ($server,$msgfile,$recipient) = @_;
    my $msg;


    open(IN,$msgfile) or return undef;
    while(<IN>)
    {
        s/%%user/$user/g;
        $msg .= $_;
    }
    close IN;

    my $smtp = Net::SMTP->new($server);
    return undef unless $smtp;
    my $rc = $smtp->mail('amaint@sfu.ca');
    if ($rc)
    {
        $rc = $smtp->to("$recipient\@sfu.ca");
        if ($rc)
        {
            $rc = $smtp->data([$msg]);
        }
        $smtp->quit();
    }
    return $rc;
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
                print STDERR "Member count returned from MLRest doesn't match maillist member count. Aborting";
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
        print STDERR "Caught error from MLRest client. Aborting";
        return undef;
    }
    return $memarray;
}


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

# Zimbra SOAP libraries for doing SOAP to Zimbra
use lib "/opt/sfu";
use IO::Socket::SSL qw(SSL_VERIFY_NONE);
# Don't check validity of server cert - it's going to fail)
IO::Socket::SSL::set_defaults(SSL_verify_mode => SSL_VERIFY_NONE);

use LWP::UserAgent;
use XmlElement;
use XmlDoc;
use Soap;
use SFUZimbra;
use SFUZimbraCommon;
use SFUZimbraClient;
use zimbrapilot;

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

# Setup for using Zimbra SOAP
my %sessionMail = (
    url      => $ZIMBRA_SOAP_URL,
    domain   => $ZIMBRA_DOMAIN,
    domain_key  => $DOMAIN_KEY,
    MAILNS   => 'urn:zimbraMail',
    ACCTNS   => 'urn:zimbraAccount',
    soap     => $Soap::Soap12,
    trace    => 0,
);

my %sessionAdmin = (
        url      => $ZIMBRA_ADMIN_URL,
        username => $ZIMBRA_USERNAME,
        password => $ZIMBRA_PASSWORD,
        domain   => $ZIMBRA_DOMAIN,
        MAILNS   => 'urn:zimbraAdmin',
        ACCTNS   => 'urn:zimbraAdmin',
        soap     => $Soap::Soap12,
        trace    => 0,
);




if (defined($ARGV[0]))
{
    $member = $ARGV[0];
    if ($member =~ /-/ && $member !~ /^(equip-|loc-)/)
    {
        print "Specified list '$member' on command line. Processing list members\n";
        $members = members_of_maillist($member);
    }
    else
    {
        print "Specified user '$member' on command line. Just processing that user\n";
        $members = [$member];
    }
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

    if (tie( %ALIASES, "DB_File","/opt/mail/aliases2.db", O_CREAT|O_RDWR,0644,$DB_HASH ))
    {
        if ($ALIASES{"$user\0"} eq "$user\@$DOMAIN\0")
        {
            print "User already migrated.";
            untie %ALIASES;
            next;
        }
        untie %ALIASES;
    }

	$res = process_q_cmd($SERVER, $EXCHANGE_PORT, "$TOKEN enableuser $user");
	if ($res !~ /^ok/)
	{
        # Failed to enable Exchange account. We can't proceed further for this user
		print $res;
        if ($res =~ /kerberos/i)
        {
            # Weird Kerberos error. Try sleeping for a bit and retrying
            # Force remote daemon to restart to get a new Exchange PS session
            process_q_cmd($SERVER, $EXCHANGE_PORT, "forcequit");
            sleep 30;
            $res = process_q_cmd($SERVER, $EXCHANGE_PORT, "$TOKEN enableuser $user");
            if ($res !~ /^ok/)
            {
                print "Second attempt, giving up and moving on: $res\n";
                next;
            }
        }
        else
        {
            next if (!$testing);
            print "Test mode so continuing anyway\n";
        }
	}

	$fail=0;

    # Exchange done, add user to Aliases on mail servers
    # We'll do the remote server first, as there's much less chance of a local failure
    $resp = process_q_cmd($targetserver,"6083","adduser $user");
    if ($resp !~ /^ok/)
    {
        $fail |= 8;
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
        	$fail |= 4;
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

    if (!$fail)
    {
        if (!(modify_zimbra_account($user,["zimbraMailStatus=disabled"])))
        {
            # We had a problem
            $fail |= 2;
        }
    }

    if ($fail > 1)
    {
        # Non-ignorable error happened - back out of Exchange account enable
        $resp = process_q_cmd($SERVER, $EXCHANGE_PORT, "$TOKEN disableuser $user");
        $res .= $resp;
        if ($fail < 9)
        {
            # Change to mailgw2 succeeded. We need to back that out
            $resp = process_q_cmd($targetserver,"6083","undo $user");
        }
        if ($fail == 2)
        {
            # Failed to communicate with Zimbra, so Aliases were changed. Undo them
            if (tie( %ALIASES, "DB_File","/opt/mail/aliases2.db", O_CREAT|O_RDWR,0644,$DB_HASH ))
            {
                $ALIASES{"$user\0"} = "$user\@$zimbramailserver\0";
                untie (%ALIASES);
            }
            if (open(MEU,"/opt/mail/manualexchangeusers") && open(NMEU,">/opt/mail/manualexchangeusers.new"))
            {
                while(<MEU>)
                {
                    print NMEU if (!/^$user:/);
                }
                close NMEU;
                close MEU;
                rename "/opt/mail/manualexchangeusers.new", "/opt/mail/manualexchangeusers";
            }
        }
    }

    $recip = $testing ? "hillman" : "$user";

    if (!$fail && !$resource)
    {
        add_message($recip,$lastemailfile);
        send_message("localhost",$firstemailfile,$recip);
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
        s/%%user/$recipient/g;
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

# Add a message to a Zimbra mailbox. This puts the message directly into the
# mailbox using SOAP, bypassing any MTAs. If the message has no Message-ID,
# none is generated (same with Date header). This may render the message
# invisible to some mail clients (it does render it invisible to the
# migration tool we're using)
sub add_message()
{
    my ($user,$msgfile) = @_;

    my $msg;
    if (!(open( IN, "<$msgfile" )))
    {
        print "Failed to open $msgfile: $!";
        return 0;
    }
    sysread(IN, $msg, 99999999);
    close(IN);
    $msg =~ s/%%user/$recipient/g;
    $msg =~ s/\r\n/\n/g;
    
    my %attributes = (
        'l'         => '/Inbox',
        'noICal'    => '1',
        'f'     => 'u'
    );

    if ( !SFUZimbraClient::get_auth_token_by_preauth( \%sessionMail, $user ) ) {
        print "Failed to auth to Zimbra";
        return 0;
    }

    my $msg_id = SFUZimbraClient::add_message(\%sessionMail, \%attributes, $msg);
    if ($msg_id)
    {
        print "Added Zimbra msg. message id: $msg_id\n";
    }
    else
    {
        print "Failed to add msg for $user. Response: $msg\n";
    }
    return $msg_id;
}

# Modify arbitrary attributes in a Zimbra account. 
# pass in attributes as an array of key=value strings
sub modify_zimbra_account() 
{
    my ($account,$attrs) = @_;

    if (! SFUZimbra::get_auth_token( \%sessionAdmin ) ) {
        print "Failed to auth to Zimbra SOAP interface\n";
        return 0;
    } 

    my $qualified_name = SFUZimbraCommon::qualify_name( $account, $sessionAdmin{'domain'} );

    my $acct_id = SFUZimbra::get_account_id( \%sessionAdmin, $qualified_name );
    if ( !$acct_id ) {
        print "Account $account is not in zimbra.\n";
        return 0;
    } else {
        my @options;
        foreach my $change (@$attrs)
        {
            if ($change !~ /[\w]+=/)
            {
                print "Attributes not in right format. Format is \"attr=value[,attr2=value2]\"";
                return 0;
            }
            my ($key,$value) = split(/=/,$change,2);
            push(@options, {$key => $value});
        }

        if ( scalar @options > 0 ) {
            if ( !$trial_run ) {
                my $success = SFUZimbra::modify_account( \%sessionAdmin, $acct_id, @options );
                if ( !$success )
                {
                    print "Failed to modify Zimbra account\n";
                    return 0;
                }
            }
        }

        return 1;
    }
}



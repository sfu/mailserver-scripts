#!/usr/bin/perl
#
# Process JMS messages for Compromised Accounts
# Connect to the JMS Broker at either the $primary_host or $secondary_host and wait
# for messages. Upon receipt of a message, process it 
#
# This script will handle anything not handled by other downstream systems. Currently, that's:
#
# - Call Amaint to reset password if msg->settings->resetpassword != false
# - Call REST server to reset Zimbra settings if msg->settings->resetzimbrasettings != false
# - Call CAS to clear CAS tokens if msg->settings->clearCASsessions != false
# - Send email to user if msg->settings->emailUser != false
# - Send email to admins if msg->settings->emailAdmins != false

use lib '/opt/amaint/etc/lib';
use Net::Stomp;
use XML::LibXML;
use HTTP::Request::Common qw(GET POST PUT DELETE);
use LWP::UserAgent;
use Canvas;
use Tokens;

$debug=0;

# If your ActiveMQ brokers are configured as a master/slave pair, define
# both hosts here. This script will try the primary, then try the failover
# host. "Yellow" == primary down, "Red" == both down
#
# If not running a pair, leave secondary_host set to undef

$primary_host = "msgbroker1.tier2.sfu.ca";
$secondary_host = "msgbroker2.tier2.sfu.ca";
#$secondary_host = undef;

$port = 61613;

$mquser = $Tokens::mquser;
$mqpass = $Tokens::mqpass;

$inqueue = "/queue/ICAT.amaint.toAmaintsupport";
$responsequeue = "/queue/ICAT.response.toAmaintsupport"; # Where we pick up status responses from

$timeout=600;		# Don't wait longer than this to receive a msg. Any longer and we drop, sleep, and reconnect. This helps us recover from Msg Broker problems too
$maxtimeouts = 3; # Max number of times we'll wait $timeout seconds for a message before dropping the Broker connection and reconnecting
$waittime = 600; # How long to wait for all responses to come in after receiving a request msg, before colating and emailing results to Admins


# =============== end of config settings ===================

# For testing
#testing();
#exit 1;

# Autoflush stdout so log entries get written immediately
$| = 1;

# Attempt to connect to our primary server

while (1) {

  $failed=0;
  eval { $stomp = Net::Stomp->new( { hostname => $primary_host, port => $port, timeout => 10 }) };

  if($@ || !($stomp->connect( { login => $mquser, passcode => $mqpass })))
  {
    # Oh oh, primary failed
    if (defined($secondary_host))
    {
		eval { $stomp = Net::Stomp->new( { hostname => $secondary_host, port => $port, timeout => 10 }) };
		if ($@)
		{
		    $failed = 1;
		    $error.=$@;
		}
		elsif(!($stomp->connect( { login => $mquser, passcode => $mqpass })))
		{
		    $failed=1;
		    $error.="Master/Slave pair DOWN. Brokers at $primary_host and $secondary_host port $port unreachable!";
		}
		else
		{
		    $error.="Primary Broker at $primary_host port $port down. Slave at $secondary_host has taken over. ";
		}
    }
    else
    {
		$failed=1;
		$error="Broker $primary_host on port $port unreachable";
    }
  }

  if (!$failed)
  {
    # First subscribe to messages from the queues
    $stomp->subscribe(
        {   destination             => $inqueue,
            'ack'                   => 'client',
            'activemq.prefetchSize' => 1
        }
    );

    $stomp->subscribe(
        {   destination             => $responsequeue,
            'ack'                   => 'client',
            'activemq.prefetchSize' => 1
        }
    );

    $counter = 0;
    do {
    	$frame = $stomp->receive_frame({ timeout => $timeout });

    	if (!$frame)
    	{
    		# Check for old requests that need to be finished off
    		foreach $serial (keys %msg)
    		{
    			cleanup($serial) if ($msg{$serial}->{time} < time() - $waittime);
    		}

    		$counter++;
    		if ($counter >= $maxtimeouts)
    		{
		    	# Got a timeout or null body back. Fall through to sleep and try again in a bit
		    	$error .="No message response from Broker after waiting $timeout seconds!";
		    	$failed=1;
		    }
		}
		else
		{
		    if (process_msg($frame->body))
		    {
			# message was processed successfully. Ack it
			$stomp->ack( {frame => $frame} );
		    }
		}
    } while ((!$failed) || defined($frame));
    $stomp->disconnect;
  }

  # Sleep for 5 minutes and try again
  if ($failed)
  {
     print STDERR "Error: $error\n. Sleeping and retrying\n";
     $failed = 0;
  }
  sleep(300);

}

# Handle an XML Message from Amaint (or Grouper?)
# Returns non-zero result if the message was processed successfully

sub process_msg
{
    $xmlbody = shift;
    $xdom  = XML::LibXML->load_xml(
             string => $xmlbody
           );

    # First, generate an XPath object from the XML
    $xpc = XML::LibXML::XPathContext->new($xdom);

    # See if we have a syncLogin message
    if ($xpc->exists("/compromisedLogin"))
    {
    	$msgtype = $xpc->findvalue("/compromisedLogin/messageType");
    	$username = $xpc->findvalue("/compromisedLogin/username");
    	$serial = $xpc->findvalue("/compromisedLogin/serial");

    	if ($msgtype =~ /request/i)
    	{
    		# New compromised account
    		$rcCas = ""; $rcAmaint = ""; $rcZimbra = "";

    		$rcCas = clearCASsessions($username) if ($xpc->findvalue("/compromisedLogin/settings/clearCASsessions") !~ /false/i);
    		$rcAmaint = resetPassword($username) if ($xpc->findvalue("/compromisedLogin/settings/resetPassword") !~ /false/i);
    		$rcZimbra = resetZimbraSettings($username) if ($xpc->findvalue("/compromisedLogin/settings/resetZimbraSettings") !~ /false/i);
    		emailUser($username) if ($xpc->findvalue("/compromisedLogin/settings/emailUser") !~ /false/i);

    		# Save the state to handle the response later
    		$msg{$serial} = {};
    		$msg{$serial}->{time} = time();
    		$msg{$serial}->{status} = $rcCas . $rcZimbra . $rcAmaint;
    		$msg{$serial}->{username} = $username;
    		$emailAdmins = "true";
    		$emailAdmins = "false" if ($xpc->findvalue("/compromisedLogin/settings/emailAdmins") =~ /false/i);
    		$msg{$serial}->{settings} = "emailAdmins=$emailAdmins";
    	}
    	elsif ($msgtype =~ /response/i) 
    	{
    		# Handle status response msgs from downstream handlers
    		if (defined($msg{$serial}))
    		{
    			$msg{$serial}->{status} .= $xpc->findvalue("/compromisedLogin/statusMsg");
    		}
    		else
    		{
    			# We never saw a request associated with this response, or we've already
    			# waited and sent the email to Admins. In either case, just
    			# ignore for now (may want to do something else later)
    		}
    	}
    }
    else
    {
		if ($debug)
		{
			($line1,$line2,$junk) = split(/\n/,$xmlbody,3);
			print "Skipping unrecognized JMS message type:\n$line1\n$line2\n$junk";
		}
		# process other JMS messages?
    }
    
    return 1;
}

sub cleanup()
{
	$msgnum = shift;
	emailAdmins($msgnum) if ($msg{$msgnum}->{settings} !~ /emailAdmins=false/i);
	delete($msg{$msgnum});
}

sub clearCASsessions()
{
	$u = shift;
	$casAdminUser = $Tokens::casAdminUser;
	$casAdminPass = $Tokens::casAdminPass;
	$casBaseURL = "https://cas.sfu.ca/cas";
	$casRestURL = $casBaseURL . "/rest/v1/";

	$casURL = $casRestURL . "tickets";

	$ua = LWP::UserAgent->new;

	# Authenticate to CAS and get a TGT
	$resp = $ua->post($casURL, {
				username => $casAdminUser,
				password => $casAdminPass
		});
	if ($resp->content eq "" || !$resp->is_success)
	{
		return "CAS Error: " . $resp->code . " " . $resp->content;
	}

	if ($resp->content !~ /(TGT-[^\"]+)\"/)
	{
		return "CAS Error. No TGT found in response: " . $resp->content;
	}
	else
	{
		$casTGT = $1;
		$casURL = $casURL . "/$casTGT";
	}

	# Got the TGT, get a Service Ticket for the activeSessions service
	$casSessionURL = $casBaseURL . "activeSessions";
	$resp = $ua->post($casURL, {
			service => $casSessionURL
		});
	if (!$resp->is_success)
	{
	    return "CAS Error: Unable to communicate with CAS to get sessions. ";
	}
	$casServiceTicket = $resp->content;


	# Now we've got a Service Ticket, we can finally fetch the sessions
	$resp = $ua->post($casSessionURL, {
			ticket => $casServiceTicket,
			id => "$u:sfu"
		});
	if (!$resp->is_success)
	{
	    return "CAS Error: Unable to communicate with CAS to get sessions. ";
	}

	# parse casResponse here (an XML doc)
    $sessionCount = 0;
    @casSessions = ();

    foreach $line (split("\n",$resp->content)) 
    {
        if ($line =~ /<cas:activeSessionsFailure code='INVALID ACCESS'>/) 
        {
            return "CAS Error: No Access to view or kill CAS sessions. ";
        } 
        elsif ($line =~ /<cas:activeSessionsFailure code='INVALID PT'>/) 
        {
            return "CAS Error: CAS session expired; can't kill CAS sessions. ";
        } 
        elsif ($line =~ /<cas:activeSessionsSuccess>/) 
        {
            $sessionCount = 0;
        }
        elsif ($line =~ /<cas:session>/) 
        {
            $sessionDate = "";
            $sessionTGT = "";
            $sessionIP = "";
        } 
        elsif ($line =~ /<cas:id>(.*)</cas:id>/) 
        {
        	$essionTGT = $1;
        }
        elsif ($line =~ /<cas:time>(.*)</cas:time>/) 
        {
        	$sessionTime = $1;
        	# Don't know what $sessionTime looks like so can't parse it yet.
        	#$sessionDate = 
        } 
        elsif ($line =~ /<cas:ip>(.*)</cas:ip>/) 
        {
            $sessionIP = $1;
        } 
        elsif ($line =~ /</cas:session>/) 
        {
            $sessionCount++;
            push (@casSessions,"$sessionTGT:$sessionIP:$sessionDate");
        }
    }

    if ($sessionCount == 0) {
        return "No CAS sessions to kill. ";
    }

    $result = "";
    foreach $sess (@casSessions)
    {
    	($ticket,$ip,$date) = split(/:/,$sess,3);
        $casURLtemp = $casRestURL . "tickets/" . $ticket;  # https://cas.sfu.ca/cas/rest/v1/tickets/TGT-180198-cEhc5z6cqqdpgeO2jVFdhezBDyBvqalYlQJ-WdDjG

        $resp = $ua->delete($casURLtemp)
        if ($resp->is_success)
        {
        	$result .= "Deleted CAS session from $ip at $date. ";
        }
    }

    return $result;

}

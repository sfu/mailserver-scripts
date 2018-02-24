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
    		# Put code in here to check if there are outstanding status responses that we need to look for 
    		#
    		#
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


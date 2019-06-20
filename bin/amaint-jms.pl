#!/usr/bin/perl
#
# Process JMS messages from Amaint
# Connect to the JMS Broker at either the $primary_host or $secondary_host and wait
# for messages. Upon receipt of a message, process it as either a user update 
# (from Amaint) or enrollment update (from Grouper)
#
# Currently, this is only used to update the Aliases2 map for mail (in /opt/mail)
# which maps 'user' to 'user@mailhost.sfu.ca'
#
# TODO: Also update aliases map from JMS messages
#

use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use Net::Stomp;
use XML::LibXML;
use HTTP::Request::Common qw(GET POST PUT DELETE);
use LWP::UserAgent;
use ICATCredentials;
use DB_File;

$debug=0;

# If your ActiveMQ brokers are configured as a master/slave pair, define
# both hosts here. This script will try the primary, then try the failover
# host. "Yellow" == primary down, "Red" == both down
#
# If not running a pair, leave secondary_host set to undef

$primary_host = "msgbroker1.dc.sfu.ca";
$secondary_host = "msgbroker2.dc.sfu.ca";
#$secondary_host = undef;

$port = 61613;

my $cred = new ICATCredentials('activemq.json') -> credentialForName('activemq');
$mquser = $cred->{'mquser'};
$mqpass = $cred->{'mqpass'};

$hostname = `hostname -s`;
chomp $hostname;
$inqueue = "/queue/ICAT.amaint.to$hostname";

if ($hostname =~ /pobox/)
{
	$mailhost = "mailhost.sfu.ca";
}
else
{
	$mailhost = "exchange.sfu.ca";
}

$timeout=600;		# Don't wait longer than this to receive a msg. Any longer and we drop, sleep, and reconnect. This helps us recover from Msg Broker problems too


# =============== end of config settings ===================

# For testing
#testing();
#exit 1;

# Autoflush stdout so log entries get written immediately
$| = 1;

# Attempt to connect to our primary server

while (1) {

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
    # First subscribe to messages from the queue
    $stomp->subscribe(
        {   destination             => $inqueue,
            'ack'                   => 'client',
            'activemq.prefetchSize' => 1
        }
    );

    do {
    	$frame = $stomp->receive_frame({ timeout => $timeout });

    	if (!$frame)
    	{
	    # Got a timeout or null body back. Fall through to sleep and try again in a bit
	    $error .="No message response from Broker after waiting $timeout seconds!";
	    $failed=1;
	}
	else
	{
	    if (process_msg($frame->body))
	    {
		# message was processed successfully. Ack it
		$stomp->ack( {frame => $frame} );
	    }
	}
    } while (defined($frame));
    $stomp->disconnect;
  }

  # Sleep for 5 minutes and try again
  if ($failed)
  {
     closemaps;
     print STDERR "Error: $error\n. Sleeping and retrying\n";
     $failed = 0;
     $error = "";
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

    # See if we have a syncLogin message. This is currently the only type of
    # message that carries new user info. We only care about userIDs that we
    # haven't seen before, so password changes, etc, can be ignored.
    if ($xpc->exists("/syncLogin"))
    {
	my (%params);
	# Add code in here to only sync certain account types?

	# Add code in here to process deletes differently?
	# Right now, the map is rebuilt nightly as well, and 
	# deletes will be dropped at that point

	$date = `date`; 
	chomp $date;

	$login_id = $xpc->findvalue("/syncLogin/username");
	$status = $xpc->findvalue("/syncLogin/login/status");

        if ($status eq 'active' || $status eq 'disabled' || $status eq 'locked') {
            &openmaps unless $debug;

	    print "$date Processing update for user $login_id\n";
            $ALIASES{$login_id."\0"} = $login_id."\@$mailhost\0";
	    closemaps();
        }
        # Ignore entries with any other status (for now?)
	else {
	    print "$date Ignoring message for $login_id. Status was $status\n";
	}	
	print $xmlbody if ($debug);
	return 1;

    }
    else
    {
	if ($debug)
	{
		($line1,$line2,$junk) = split(/\n/,$xmlbody,3);
		print "Skipping unrecognized JMS message type:\n$line1\n$line2\n$junk";
	}
	# process Grouper JMS messages?
    }
    
    return 1;
}

sub openmaps {
    if (!$OPEN) {
	tie( %ALIASES, "DB_File","$MAILDIR/aliases2.db", O_CREAT|O_RDWR,0644,$DB_HASH )
  	  || die("Can't open aliases map $MAILDIR/aliases2.db. Can't continue!");
        $OPEN=1;
    }
}

sub closemaps {
    return if !$OPEN;
    untie(%ALIASES);
    $OPEN=0;
}


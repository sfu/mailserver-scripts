#!/usr/bin/perl
#
# Process JMS messages for requests to kill CAS sessions
# Connect to the JMS Broker at either the $primary_host or $secondary_host and wait
# for messages. Upon receipt of a message, process it 
#
# Inbound message requests come via the ICAT.amaint.toCas queue. Either XML or JSON are
# supported and the same format will be used for responses (if a response is requested)
# Format of a request (in XML):
#<clearCasSessions>
#  <username>kipling</username>
#  <serial>123456789</serial>
#  <respond>ICAT.casAdmin</respond>
#</clearCasSessions>
#
# The 'serial' and 'respond' attributes are optional. If left out, no response will be sent.
# You may also send the request as type "compromisedLogin" instead of "clearCasSessions". 
# Responses for this message type are always sent to ICAT.response.toAmaintsupport


use lib '/opt/amaint/lib';
use Net::Stomp;
use XML::Simple;
use JSON;
use LWP;
use URI::Escape;
use ICATCredentials;
use Getopt::Std;
use Data::Dumper;

getopts("v");

$debug = $opt_v;

# Fetch all settings from the "Credentials" file
my $cred  = new ICATCredentials('activemq.json')->credentialForName('client');
foreach $s (qw(primary_host secondary_host stomp_port amquser amqpass casuser caspass casbaseurl))
{
    if (!defined($cred->{$s}))
    {
        die "$s not defined in activemq.json credentials file";
    }
}
my $primary_host = $cred->{'primary_host'};
my $secondary_host = $cred->{'secondary_host'};
my $port = $cred->{'stomp_port'};
my $mquser = $cred->{'amquser'};
my $mqpass = $cred->{'amqpass'};
my $casuser = $cred->{'casuser'};
my $caspass = $cred->{'caspass'};
my $cas_server = $cred->{'casbaseurl'};


$inqueue = "/queue/ICAT.amaint.toCas";
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

        $counter = 0;
        do {
            $frame = $stomp->receive_frame({ timeout => $timeout });

            if (!$frame)
            {
                $counter++;
                if ($counter >= $maxtimeouts)
                {
                    # Got a timeout or null body back. Fall through to sleep and try again in a bit
                    $error .="No message response from Broker after waiting $timeout seconds!";
                    $failed=2;
                }
            }
            else
            {
                $json = ($frame->content-type =~ /json/);
                if (process_msg($frame->body))
                {
                    # message was processed successfully. Ack it
                    $stomp->ack( {frame => $frame} );
                }
            }
        } while ((!$failed) || defined($frame));
        $stomp->disconnect;
    }

    if ($failed == 2)
    {
        # Got more than $maxtimeouts timeouts, but that just means no activity.
        # Sleep a few seconds and reconnect
        print "No frames in $timeout seconds\n" if $debug;
        sleep 3;
        next;
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
    if ($json)
    {
        $xref = decode_json($json);
    }
    else
    {
        $xref = XMLin($xmlbody, KeepRoot => 1);
    }
    my $clear=0;

    print "Processing message:\n$xmlbody\n As: ",Dumper($xref),"\n" if $debug;

    # See if we have a syncLogin message
    if (defined($xref->{"compromisedLogin"}))
    {
        $xpc = $xref->{"compromisedLogin"};
    }
    elsif (defined($xref->{"clearCasSessions"}))
    {
        $xpc = $xref->{"clearCasSessions"};
        $clear=1;
    }
    else
    {
		if ($debug)
		{
			($line1,$line2,$junk) = split(/\n/,$xmlbody,3);
			print "Skipping unrecognized JMS message type:\n$line1\n$line2\n$junk";
		}
		# process other JMS messages?

        return 1;
    }
    my $msgtype = $xpc->{"messageType"};
    my $username = $xpc->{"username"};
    my $serial = $xpc->{"serial"};
    my $response_queue = $xpc->{"respond"};


    if ($clear || ($msgtype =~ /request/i && $xpc->{"settings"}->{"clearCASsessions"} !~ /false/i))
    {
        ($rcCas,@sessions) = clearCASsessions($username,$casuser,$caspass);
        if ($clear)
        {
            if (defined($response_queue))
            {
                send_response($response_queue,"clearCasSessions",$username,$serial,$rcCas,@sessions);
            }
        }
        else
        {
            send_response($responsequeue,"compromisedLogin",$username,$serial,$rcCas,@sessions);
        }

        # Log results to STDOUT
        print "Command: clearCasSessions for user $username\n";
        print "Result: $rcCas\nSessions: ",join("\n",@sessions,"");
    }
    
    return 1;
}

sub clearCASsessions()
{
	my ($u,$casAdminUser,$casAdminPass) = @_;

    $ua = LWP::UserAgent->new;

    my $tgt = cas_rest_login($casAdminUser,$casAdminPass);

    if (!defined($tgt))
    {
        return "500 REST login failed";
    }

    # Got a basic login ticket, now get a service ticket for the activeSessions service
    # The activeSessions service has a hard-coded Service string, regardless of what CAS
    # instance it's running on
    my $svcurl = "https://cas.sfu.ca/cas/activeSessions";
	my $res = post_page_raw($cas_server."/v1/tickets/$tgt", ["service=$svcurl"]);
	if (!$res->is_success)
	{
        print "Failed to get Service Ticket\n";
	    return "500 Failed to get CAS Service Ticket";
	}
	my $casServiceTicket = $res->content;

    # Make the activeSessions request
    $res = post_page_raw($cas_server."/activeSessions",["ticket=$casServiceTicket","id=$u:sfu"]);
    if (!$res->is_success)
	{
        return "500 ". $res->status_line;
	}

    my $xmlref = XMLin($res->content);

    print "CAS activeSessions data:\n",Dumper($xmlref),"\n" if $debug;

   # Verify the right elements are present
    return "500 No CAS Sessions retrieved" if (!defined($xmlref->{'cas:activeSessionsSuccess'}));
    return "404 No CAS Sessions" if (!defined($xmlref->{'cas:activeSessionsSuccess'}->{'cas:session'}));

    # Walk the results and delete all tickets except the one for this session
    my $sessions = $xmlref->{'cas:activeSessionsSuccess'}->{'cas:session'};
    $killed = 0;
    my @results;

    # If there was only one session, convert to an Array with one element
    if (ref($sessions) ne "ARRAY" )
    {
        $sessions = [$sessions];
    }

    foreach my $s (@$sessions)
    {
        $res = $ua->delete("$cas_server/v1/tickets/".$s->{'cas:id'});
        if ($res->is_success)
        {
            $killed++;
            push (@results,$s->{'cas:ip'} . ":" . $s->{'cas:time'} . ":SUCCESS");
        }
        else
        {
            push (@results, $s->{'cas:ip'} . ":" . $s->{'cas:time'} . ":WARNING: Couldn't kill TGT " . $s->{'cas:id'});
        }
    }

    return "200 No CAS sessions killed" if (!$killed);

    return("200 Killed $killed CAS sessions",@results);

}

sub send_response()
{
    my ($response_queue,$msgtype,$user,$serial,$status,@sessiondata) = @_;
    $responseref = {};
    $responseref->{$msgtype} = {
        messageType => "Response",
        username => $user,
        serial => $serial,
        serviceName => "CAS",
        statusMsg => $status,
        casSessions => []
    };

    foreach $s (@sessiondata)
    {
        ($ip,$s_date,$msg) = split(/:/,$s,3);
        push ($responseref->{$msgtype}->{casSessions}, {
            ipAddress => $ip,
            time => int($s_date/1000),
            result => $msg
        });
    }
   
   $responsemsg = ($json) ? encode_json($responseref) : XMLout($responseref, KeepRoot => 1, NoAttr => 1);
   $content_type = ($json) ? "application/json" : "application/xml";

    $stomp->send({
        destination  => $response_queue,
        content-type => $content_type,
        body         => $responsemsg
    });

    print "Response Message:\n$responsemsg\n" if $debug;
}

# Post to a URL and return the raw content
sub post_page_raw
{
    my ($url,$data,$follow_redirects) = @_;
    my $req = HTTP::Request->new(POST => $url);
    $req->content_type('application/x-www-form-urlencoded');

    if (defined($data))
    {
        my $postdata = "";
        foreach $l (@$data)
        {
            ($k,$v) = split(/=/,$l,2);
            $val = uri_escape($v);
            $postdata .= ($postdata eq "") ? "" : "&";
            $postdata .= "$k=$val";
    	}
    	$req->content($postdata);
        print "Sending: \n$postdata\n\n" if $opt_v;
    }
	     
    my $res = ($follow_redirects) ? $ua->request($req) : $ua->simple_request($req);
    print "RESULT: ",$res->status_line,"\n" if $opt_v;

    return $res;
}

sub cas_rest_login
{
    my ($u,$p) = @_;
    my $TGT;

    my $res =  post_page_raw("$cas_server/v1/tickets", ["username=$u","password=$p"] );
    if (!$res->is_success)
    {
        return undef;
    }

    $loc = $res->header("Location");
    if ($loc =~ /v1\/tickets\/(TGT.+)/)
    {
        $TGT = $1;
    }
    return $TGT;
}
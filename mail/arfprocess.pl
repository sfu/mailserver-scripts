#!/usr/bin/perl
#
# Process Abuse Response Feedback messages from AOL and Hotmail. We get one of these
# messages whenver their user marks a message as spam that came from an SFU
# IP address. The message consists of multiple MIME parts, the last of which
# is the actual offending message -- that's all we care about.
#
# Unless there's a compromised machine or account, the most common cause of this
# is stupid users who mark posts to mailing lists as spam, or simply accidentally
# hit the "is spam" button. As such, we want to keep a record of all marked
# messages and only alert an admin if we get at least 3 originating from the same 
# user or IP. We automatically skip anything coming from a mailing list (From is 'owner-')
#
# Messages that come from SFUWebmail have an X-Sender: header. From Zimbra, they
# have an X-Authenticated-User header. And if they have neither of these, parse
# the 'Received' headers looking for the IP.
#

use Mail::Internet;
use DB_File;

sub logtofile($);

# Wherever the logfile goes, it must be writeable by the user that sendmail runs scripts as, typically "mail"
$logfile = "/var/log/arf.log";

# Ideally this should be space shared between all mailserver nodes. Must be writeable by the user sendmail runs scripts as
$senderdb = "/home/hillman/arf.db";

# Who to send alerts to. Typically this will be your mail abuse team
$notify = "hillman\@sfu.ca,abuse\@sfu.ca";

$now = time();

# Suck in the message from stdin. Skip down to the attached message part
@message = <STDIN>;

$found = 0;

foreach $l (@message)
{
    next if ($l !~ /Content-Type: message\/rfc822/ && !$found);
    $found = 1;
    push (@msg,$l); 
}

if (!$found)
{
    # No message attachment was found. This mustn't be an ARF message
    @msg = @message;
    sendalert();
    exit 0;
}

# Ditch the junk before the headers of the attached message
do {
    shift (@msg);
} until ($msg[0] =~ /^Return-Path|Received:|X-HmXmrOriginalRecipient:/ || !$msg[0]);

# Now @msg contains our "spam"
# Stuff it into an object for easier processing

@savemsg = @msg;

$mob = new Mail::Internet(\@msg);

# Stuff the headers into an object
$head = $mob->head();

# Check the Return-Path
if (defined($head->get('Return-Path')))
{
    $rp = $head->get('Return-Path');

    ### CUSTOMIZE the regex in the next line to be able to match messages from mail lists from your site
    if ($rp =~ /owner-.*@(mailgw|rm-rstar)(1|2).sfu.ca/)
    {
	# Mailing list. Skip it
	logtofile("Skipping message. Came from SFU mailing list\n");
	exit 0;
    }
}

$sender = $head->get('X-Sender') or $sender = $head->get('X-Authenticated-User');

if(defined($sender))
{
    chomp($sender);
    # Message came from Zimbra or SFUWebmail
    process_sender($sender);
}
else
{
    # Check to see if the To: was an SFU address. If it was, this
    # is almost certainly just a forwarded message marked as spam
    $to = $head->get('To');
    if ($to =~ /^[^,;]+\@.*sfu.ca>?$/)
    {
	# Message contained just one sfu.ca recipient, so it's not spam
	# that we can do anything about
	logtofile("Skipping message to sfu.ca recipient: To: $to");
	exit 0;
    }

    # Retrieve the sender's IP address from Received headers
    $head->unfold('Received');
    @recvd = $head->get('Received');
    $found = 0;
    foreach $recv (reverse(@recvd))
    {
	### CUSTOMIZE the following regex's to match messages received by your site's designated mail servers
    	if  ($recv =~ /by (mailgw|rm-rstar)(1|2).sfu.ca/i || 
	     $recv =~ /by pobox.sfu/i || 
	     $recv =~ /by pobox(1|2).f5esx.sfu/i || 
	     $recv =~ /from .*142\.58.*\sby/i ||
	     $recv =~ /from .*192\.75\.242.*\sby/i )
	{
	   # Skip the header for the one coming from rm-rstar or pobox. Doesn't help us
	   next if ($recv =~ /from (rm-rstar|pobox|mailgw)\d?.sfu.ca/);
	   $found = $recv;
	   last;
	}
    }
    if ($found)
    {
	if ($found =~ /from .+[^\d]+(\d+\.\d+\.\d+\.\d+).+by/i)
	{
	    $sender = $1;
	}
	else
	{
	    $sender = $found; 
	    $sender =~ s/by.*//i;
	}
	process_sender($sender);
    }
    else
    {
	# Couldn't identify this message properly, better just forward it
	sendalert();
    }
}

exit 0;

sub logtofile($)
{
	$log = shift;
	$mid = $head->get('Message-ID');
	chomp($mid);
	open(LOG,">>$logfile");
	print LOG scalar localtime();
	print LOG $mid,": ",$log;
	close LOG;
}

sub process_sender()
{
    $s = shift;
    dbmopen(%arfdb,$senderdb,0666);
    tie(%arfdb,"DB_File",$senderdb,O_RDWR,0666);
#    if ($arfdb{"$s.time"} < $now - (7*86400))
    $c = $arfdb{"$s.count"};
    $c++;
    $arfdb{"$s.count"}=$c;
    untie(%arfdb);
    if ($c == 1 || $c == 3 || $c == 6 || (!($c%10))|| $s eq "142.58.101.11")
    {
	sendalert($s,$c);
    }
    logtofile("processed report for $s. Count = $c\n");
}

sub sendalert()
{
    ($from,$count) = @_;
    if (defined($from))
    {
	$subj = "ARF: for $from recvd $count times";
    }
    else
    {
	$subj = "ARF: Unidentifiable report received";
    }

    open(OUT,"|/usr/sbin/sendmail $notify");
    print OUT <<EOM;
From: AOL Abuse Processor <aolabuse\@sfu.ca>
To: $notify
Subject: $subj

Reported message is below:

@savemsg
EOM
    close OUT;
    logtofile("Forwarding to admin\n");
}

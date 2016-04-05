#!/usr/local/bin/perl -w
use Sys::Syslog;
use Mail::Internet;
use MIME::Base64;
use Encode qw/encode decode/;
require 'getopts.pl';
use lib '/opt/mail/maillist2/bin';
use LOCK;
use lib '/opt/mail/maillist2/bin/test';
use MLCache;
use MLMail;
use SFULogMessage;
use SFUAppLog qw( log );

use vars qw($main::fromheader);
select(STDOUT); $| = 1;         # make unbuffered
$SIG{'INT'}  = 'IGNORE';
$SIG{'HUP'}  = 'IGNORE';
$SIG{'QUIT'} = 'IGNORE';
$SIG{'PIPE'} = 'IGNORE';
$SIG{'ALRM'} = 'IGNORE';

use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;
use constant EX_UNAVAILABLE => 69;

use constant LOCK_SH => 1;
use constant LOCK_EX => 2;
use constant LOCK_NB => 4;
use constant LOCK_UN => 8;

#$QFOLDER  = "/opt/mail/maillist2/mlqueue";
$main::MLROOT = "/tmp/maillist2";
$QFOLDER  = $main::MLROOT."/mlqueue";

$maillistname = $ARGV[0];
$maxspamlevel = $ARGV[1];

$main::TEST = 1;
$main::DELIVER = 0;

openlog "mlqtest", "pid", "mail";
syslog("info", "mlqtest started for $maillistname");
syslog("info", "mlqtest max spam level for $maillistname is $maxspamlevel");
my $msg  = Mail::Internet->new( STDIN );
$msg->print();
my $headers = $msg->head();
my $id = $headers->get("Message-Id");
chomp $id;
$id =~ s/^<|>$//g;
syslog("info", "No Message-Id header in message") unless $id;
$id = _genMsgId() unless $id;                # Message-Id not set; create one
syslog("info", "mlq processing message id %s for $maillistname", $id);
my $subject = $headers->get("Subject");
if (($subject =~ /^Delivery Status Notification/) || ($subject =~ /^NOTICE: mail delivery status/)) {
   syslog("info", "Message %s to %s rejected - Delivery Status Notification.", $id, $maillistname);
   closelog();
   exit EX_OK;
}
if ( $subject =~ /[[:^ascii:]]/ ) {
   syslog("info", "%s Message contains non-ascii characters in subject:", $id);
   $subject = encode('MIME-Q', $subject);
}
printf("\nMessage subject: %s\n", $subject) if $main::TEST;
   
my $fromheader = $headers->get("From") unless $fromheader;
chomp $fromheader;
unless ($fromheader) {
   syslog("info", "Message %s to %s rejected - missing From header.", $id, $maillistname);
   closelog();
   exit EX_OK;
}
syslog("info", "Message %s to %s from %s", $id, $maillistname, $fromheader);

my $mlinfo = new MLCache($maillistname, $main::MLROOT);

my $spamlevel = 0;
my $barracudascore = $headers->get("X-Barracuda-Spam-Score");
chomp $barracudascore;
if ($barracudascore) {
   $spamlevel = $barracudascore;
} else {
	$spamlevel = numeric_spamlevel($headers->get("X-Spam-Level"));
}
if ($spamlevel > $maxspamlevel) {
	syslog("info", "Message %s to %s rejected due to spam rating %s.", $id, $maillistname, $spamlevel);
	if ($mlinfo->bounceSpamToModerator()) {
		syslog("info", "Bouncing message %s to %s moderator.", $id, $maillistname);
        # get the from address
        $fromheader = $headers->get("From") unless $fromheader;
        my $from = ((Mail::Address->parse($fromheader))[0])->address();
		_bounceToModerator($from,$mlinfo,$msg,"message rejected due to spam rating");
	}
   closelog();
   exit EX_OK;
}

my $dir = &getMsgDirName($id);
syslog("info", "mlq message id %s will be saved in %s", $id, $QFOLDER."/".$dir);

unless (acquire_lock("$QFOLDER/$dir.lock")) {
	syslog("info", "mlq %s error getting lock file %s: $!", $id, "$QFOLDER/$dir.lock");
	closelog();
	exit EX_TEMPFAIL;
}
	
if (!-e "$QFOLDER/$dir") {
    mkdir "$QFOLDER/$dir" ;                    # create a queue folder for msg
    chmod 0775, "$QFOLDER/$dir";
    
    # put the msg id in 'id' file
    open ID, ">$QFOLDER/$dir/id";
    print ID $id;
    close ID;
    # put the msg in 'msg' file
    open $main::MSG, ">$QFOLDER/$dir/msg";
    $msg->print($main::MSG);                 
    close $main::MSG;
    syslog("info", "Added message %s to maillist queue: %s", $id, $dir);
}
# put maillist name in 'addrs' file
open $main::ADDRS, ">>$QFOLDER/$dir/addrs";
flock $main::ADDRS, LOCK_EX;
seek $main::ADDRS, 0, 2; # in case someone appended while we were waiting
print $main::ADDRS "$maillistname\n";
close $main::ADDRS;
release_lock("$QFOLDER/$dir.lock");
syslog("info", "Added '%s' to delivery list for message: %s", $maillistname, $id);
_appLog($maillistname, $fromheader, $id, $subject) unless $maillistname eq 'zimlet-debug';
closelog();
exit EX_OK;

sub _genMsgId {
	return time . "." . (int(rand 10000) + 1) . "." . (int(rand 10000) + 1) . "\@mlq.sfu.ca";
}
	
sub numeric_spamlevel {
	my($spamlevel_hdr) = @_;
	chomp $spamlevel_hdr;
	$spamlevel_hdr =~ /Spam-Level (S*)/;
	my $spamlevel = $1;
	$spamlevel =~ s/^\s*//;
	return length($spamlevel);
}

sub getMsgDirName {
	my $id = shift;
	my $b64id = encode_base64( $id, "" );
	if (250 < length $b64id) {
		return substr($b64id,-250);
	} 
	$b64id =~ tr/\//_/; # MIME b64 charset uses '/' char, which won't work for a directory name.
	return $b64id;
}

sub _bounceToModerator {
    my ($sender, $mlinfo, $msg, $subjectMsg) = @_;
    my $moderator = $mlinfo->effectiveModerator();
    my $listname = $mlinfo->name();
    my $body = "Original message follows:\n\n";
    $body .= $msg->as_string();
    #$body .= $msg->head()->as_string();
    #$body .= join "",@{$msg->body()};
    _sendMail( $moderator ? $moderator : "owner-$listname", "Bounce to moderator of \"$listname\": $subjectMsg", $body, $sender );
}

sub _sendMail {
    my ($to, $subject, $body, $from) = @_;
    if ($main::TEST) {
      print "Sending mail:\n";
      print "to: $to\n";
      print "from: $from\n";
      print "subject: $subject\n";
      print "body: $body\n";
    }
    if ($main::DELIVER) {
    	my $sendmail = '/usr/lib/sendmail';
    	open(MAIL, "|$sendmail -oi -t");
    	print MAIL "From: $from\n";
    	print MAIL "To: $to\n";
    	print MAIL "Subject: $subject\n\n";
    	print MAIL "$body\n";
    	close(MAIL);
    }
}

sub _appLog {
    my ($maillistname, $fromheader, $id, $subject) = @_;
    my $from = ((Mail::Address->parse($fromheader))[0])->address();
    my $canonicalAddress = MLMail::canonicalAddress($fromheader);
    my $msg = new SFULogMessage();
    $msg->setEvent("message queued");
    $msg->setDetail("$id to: $maillistname; from: $from; subject: $subject");
    $msg->setAppName("mlq");
    $msg->setTags(["$maillistname","$canonicalAddress","#mldelivery"]);
    my $APPLOG = new SFUAppLog();
    $APPLOG->log('/queue/ICAT.test.log',$msg);
}

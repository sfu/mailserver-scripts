#!/usr/bin/perl
#
# Change log:
#  2006/11/15 Resolve issue ML-2
#  2007/05/10 Resolve issue ML-62
#  2007/05/14 Resolve issue ML-17
#  2015/10/28 Resolve issue ML-446
#
use Sys::Syslog;
use Mail::Internet;
use Mail::Address;
use Mail::Send;
use Digest::MD5;
#
# mlproxy requires an absolute lib path, as it runs from /etc/smrsh
use lib '/opt/amaint/maillist/lib';
use Paths;
use MLMail;
use MLCache;
use MLRestClient;
use MLRestMaillist;
use ICATCredentials;
use Getopt::Std;
@nul = ('not null','null');
select(STDOUT); $| = 1;         # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';
use constant OWNERONLY => 30;
use constant BYREQUEST => 20;
use constant DEBUG => 0;
@DOMAINS = ("sfu.ca",
        "sfu.edu",
        "smtp.sfu.ca",
        "smtpserver.sfu.ca",
        "mail.sfu.ca",
        "mailserver.sfu.ca",
        "mailhost.sfu.ca",
        "rm-rstar.sfu.ca",
        "pop.sfu.ca",
        "popserver.sfu.ca",
        "fraser.sfu.ca" );

$LISTNAME = $ARGV[0];
$PREFIX = "";

# Note: the user 'nullmail' which is the user that runs sendmail must have read access to /usr/local/credentials/maillist.json
my $mlrest = new ICATCredentials('maillist.json')->credentialForName('robert');
my $client = new MLRestClient($mlrest->{username},$mlrest->{password},0);

openlog "ml2proxy", "pid", "mail";
syslog("notice", "mlproxy started");

#
# If it's a confirmation message reply:
#   Process confirmation message reply.
# else:
#   Get the list info.
#   If subscribe:
#     If the subscription policy is owner-only:
#       Send reply, with directions to send message to owner-list-name.
#     else:
#       Send subscribe confirmation message.
#   else:
#     Send unsubscribe confirmation message.
#

my %seen = ();
$main::md5 = Digest::MD5->new;
my $msg  = Mail::Internet->new( STDIN );
my $headers = $msg->head();
$sender = _getSender($headers);
my $subjecthdr = $headers->get("Subject");
if ($subjecthdr=~/^[rR][eE]:/) {
	$subjecthdr = substr($subjecthdr,3);
}
$subjecthdr =~ s/^\s+//;
$subjecthdr =~ s/\s+$//;
syslog("notice", "subjecthdr:$subjecthdr");

my @subject = split /\s+/,$subjecthdr;
my $cmd = lc $subject[0];
$LISTNAME = lc $subject[1] unless $LISTNAME;

my $info = $client->getMaillistByName( $LISTNAME );
if (!$info)
{
	syslog("notice","mlproxy exited for sender $sender and cmd \"$cmd\". $LISTNAME does not exist or MLREST call failed to fetch it");
	exit 0;
}
    
if ($#subject==3 && (lc $subject[2]) eq 'confirmation') {
	my $digest = $subject[3];
	if ($digest =~ /^\"/ || $digest =~ /^\'/) {
		#strip quotes
		chop $digest;
		$digest = substr( $digest, 1 );
	}
	_processReply(_getCommand($cmd), $LISTNAME, $sender, $digest);
} else {
	syslog("notice", "mlproxy processing $LISTNAME");
	
    $moderator = $info->{'moderator'};
    $moderator = $info->{'owner'} unless ($moderator);
	$cmd = _getCommand($cmd);        
	my $digest = _generateDigest($sender, $cmd, $LISTNAME);
	my $subject = $cmd.' '.$LISTNAME.' Confirmation "'.$digest.'"';
	
	if ($cmd eq 'subscribe') {
	   my $policy = _subscriptionPolicyForSender($info, $sender);
	   print("policy:$policy\n") if DEBUG;
	   if ($policy==OWNERONLY || $policy == BYREQUEST) {
	      # send reply with directions
          _sendMailFromTemplate("subNotAllowed", $sender, 'Maillist error', $LISTNAME);
	   } else {
          print("send confirmation\n") if DEBUG;
	      # send subscribe confirmation message
	      	syslog("notice", "sending subscribe $LISTNAME confirmation for $sender");
	      	syslog("notice", " with subject:$subject");
          _sendMailFromTemplate("sub1", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca" );
	   }
	} elsif ($cmd eq 'unsubscribe') {
	   if (!_isMember($info, $sender)) {
          	_sendMailFromTemplate("notMember", $sender, 'Maillist error', $LISTNAME);
	   } elsif ($info->{'canUnsubscribe'} || !MLMail::isLocalAddress($sender)) {
	      	# Send unsubscribe confirmation message
	      	syslog("notice", "sending unsubscribe $LISTNAME confirmation for $sender");
          		_sendMailFromTemplate("unsub1", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca");
       	    } elsif ($info->{'type'} != 0) {
          		_sendMailFromTemplate("dynamicMember", $sender, 'Maillist error', $LISTNAME);
       	    } else {
          		_sendMailFromTemplate("unsubNotAllowed", $sender, 'Maillist error', $LISTNAME);
       	    }
	} elsif ($cmd eq 'help') {
	   	$subject = $LISTNAME." help";
	   	my $mlc = new MLCache($LISTNAME);
	   	$description = $mlc->{'desc'};
	   	my $policy = _subscriptionPolicyForSender($info, $sender);
	   	if ($mlc->{'type'}!=0) {
       		_sendMailFromTemplate("help_noinfo", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca");
	   	} elsif ($policy!=OWNERONLY && $policy != BYREQUEST) {
          	_sendMailFromTemplate("help", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca");
       	} elsif ($mlc->isMemberOfExpandedList($sender, \%seen)) {
          	_sendMailFromTemplate("help_no_sub", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca");
       	} else {
          	_sendMailFromTemplate("help_noinfo", $sender, $subject, $LISTNAME, "$PREFIX$LISTNAME-request\@sfu.ca", "$PREFIX$LISTNAME-request\@sfu.ca");
       	}
	} else {
	   # Not a known command. Forward to owner/moderator.
       	my $body = join "",@{$msg->body()};
   		my $to = join ',',$moderator;
       	_sendMail( $to, $subjecthdr, $body, $sender." ($sender via $PREFIX$LISTNAME-request)" );
	}
	
}

closelog();
0;

sub getErrMessage {
	my $result = shift;

	syslog("err", "Error getting information for $LISTNAME -> ". toString($result));
	return "Unknown error";
}
		 
sub _generateDigest {
	my ($sender, $cmd, $list) = @_;
	
    $main::md5->add('sc9;3Mq#',$sender,$cmd,$list);
    return $main::md5->b64digest;
}

sub _processReply {
	my ($cmd, $list, $sender, $digest) = @_;
	my $msg = "";
	my $result = "";
	my $template = "";
	
	syslog("notice", "_processReply cmd:$cmd");
	syslog("notice", "_processReply list:$list");
	syslog("notice", "_processReply sender:$sender");
	syslog("notice", "_processReply digest:$digest");

	my $newdigest = _generateDigest($sender, $cmd, $list);
	syslog("notice", "_processReply newdigest:$newdigest");
	if ($newdigest eq $digest) {
		syslog("notice", "executing: $cmd $list for $sender");
		
		if ($cmd eq 'subscribe') {
			$result = _subscribeViaEmail( $list, $sender );
			$template = "sub2";
		} elsif ($cmd eq 'unsubscribe') {
			$result = _unsubscribeViaEmail( $list, $sender );
			$template = "unsub2";
		} else {
			$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\nReason:\"".cmd."\" is not a valid command";
			_sendMail( $sender, 'Maillist error', $msg );
		}
		
		if (defined($result)) {
			_sendMailFromTemplate($template, $sender, 'Maillist Confirmation', $list);
		} else {
				$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\n";
				_sendMail( $sender, 'Maillist error', $msg );
		}
	} else {
		$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\nReason:Message authentication failed";
		_sendMail( $sender, 'Maillist error', $msg."digest:$digest newdigest:$newdigest" );
	}
}

sub _subscriptionPolicyForSender {
	my ($info,$sender) = @_;
	if (isLocalAddress($sender)) { 
	   print "$sender is local address\n" if DEBUG;
	   return $info->localSubscriptionPolicy();
	}
	return $info->externalSubscriptionPolicy();
}

sub _canUnsubscribe {
	my ($info,$sender) = @_;
	if ($info->{'type'}==0) { return 1; }
	return $info->externalSubscriptionPolicy();
}

sub _sendMail {
	my ($to, $subject, $body, $from) = @_;
	my $msg = new Mail::Send;
    $msg->to($to);
    $msg->to(@$to) if ref $to;
    $msg->subject($subject);
	$msg->set("From",($from)) if $from;
    my $fh = $msg->open('sendmail');
    print $fh $body;
    $fh->close;
}

sub _sendMailFromTemplate {
	my ($template,$to,$subject,$listname,$from,$replyto) = @_;
	my $text="";
	my $msg = new Mail::Send;
	$msg->to($to);
	$msg->subject($subject);
	$msg->set("From",($from)) if $from;
	$msg->set("Reply-To",($replyto)) if $replyto;
	my $fh = $msg->open('sendmail');
	open(TEMPLATE, "$MAILLISTDIR/templates/$template");
	while($text=<TEMPLATE>) {
		$text =~ s/(\$\w+)/$1/eeg;      
		print $fh $text;
	}
	$fh->close;
}

sub _bounceToModerator {
    my ($sender, $listname, $msg) = @_;
    my $headers = $msg->head();
    my $subject = $headers->get("Subject");
    my $body = join "",@{$msg->body()};
    _sendMail( @main::MODERATORS, $subject, $body, $sender );
}

sub _getSender {
	my ($headers) = @_;
	
	my $address = $headers->get("Reply-To");
	if (!$address) {
		$address = $headers->get("From");
	}

	my @addrs = Mail::Address->parse($address);
	my $addr = $addrs[0];
	return MLMail::canonicalAddress($addr->address);
}

sub _getCommand {
	my ($cmd) = @_;
	
	return 'subscribe' if $cmd =~  /^(sub|subscribe|join)$/;
	return 'unsubscribe' if $cmd =~ /^(unsub|unsubscribe|resign|remove)$/;
	return 'help' if $cmd =~ /^(help|info|information)$/;
	return $cmd;
}

sub _subscribeViaEmail {
	my ($listname, $address) = @_;
UPD: 
    for ($attempt = 0; $attempt < 5; $attempt++) {
        eval '$main::response = $client->addMember($info, $address );';
        if (!defined($main::response)) {
            if ($main::HTTPCODE =~ /500/ || $$main::HTTPCODE =~ /404/) {
                sleep 30;
                next;
            }
            my $msg = "_subscribeViaEmail failed for $listname, $sender";
			_sendMail( "amaint\@sfu.ca", 'mlproxy error', $msg );
		}
        last;
    }
	return $main::response;
}

sub _unsubscribeViaEmail {
	my ($listname, $address) = @_;
UPD: 
    for ($attempt = 0; $attempt < 5; $attempt++) {
        eval {
        	$member = $client->getMemberForMaillistByAddress($info,$address);
        	if ($member)
        	{ 
        		$main::response = $client->deleteMember($member);
        	}
        	else
        	{
        		syslog("notice","$address not in $listname");
        		die "$address not in $listname"
        	}
        };
        if ($@ || (!defined($main::response))) {
            if ($main::HTTPCODE =~ /500/ || $$main::HTTPCODE =~ /404/) {
                sleep 30;
                next;
            }
            my $msg = "_unsubscribeViaEmail failed for $listname, $sender :$@";
			_sendMail( "amaint\@sfu.ca", 'mlproxy error', $msg );
		}
        last;
    }
	return $main::response;
}

sub _noDomainSpecified {
	my ($address) = @_;
	return index($address,'@')==-1;
}

sub hasLocalDomain {
	my ($address) = @_;
	my $domain = substr($address, index($address,'@')+1);
	return scalar grep /^$domain$/,@DOMAINS;
}

sub isLocalAddress {
	my ($address) = @_;
	return _noDomainSpecified($address) || hasLocalDomain(lc $address);
}

sub _isMember {
	my ($info, $sender) = @_;
	my @memArr = $info->members;
	my %memHash;
	foreach my $mem (@memArr) {
		$memHash{$mem->{'canonicalAddress'}} = 1;	
	}
	return exists($memHash{$sender});
}

sub toString {
    $self = shift;
    my $str = '';
    
    foreach $key (keys %$self) {
      $str .= "$key: ";
      $str .= $self->{$key};
      $str .= "\n";
    }
    return $str;
}

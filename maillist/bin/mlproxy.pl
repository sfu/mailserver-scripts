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
use SOAP::Lite ;
#
# mlproxy requires an absolute lib path, as it runs from /etc/smrsh
use lib '/opt/amaint/maillist/lib';
use Paths;
use MLMail;
use MLCache;
use MLRestClient;
use MLRestMaillist;
use ICATCredentials;
require 'getopts.pl';
@nul = ('not null','null');
select(STDOUT); $| = 1;         # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';
use constant OWNERONLY => 30;
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
my $mlrest = new ICATCredentials('maillist.json')->credentialForName('mlrest');
my $client = new MLRestClient($mlrest->{username},$mlrest->{password},0);

my $info = $client->getMaillistByName( $LISTNAME );
unless ($info) { print "Not defined\n"; exit(0); }

# TODO: Need to convert from SOAP to REST
$main::TOKEN = $mlrest->{soapToken};
my $serviceurl = $mlrest->{soapUrl};
$main::SERVICE = SOAP::Lite
        -> ns_uri( $serviceurl )
        -> proxy( $serviceurl );

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
my $sender = _getSender($headers);
my $subjecthdr = $headers->get("Subject");
if ($subjecthdr=~/^[rR][eE]:/) {
	$subjecthdr = substr($subjecthdr,3);
}
$subjecthdr =~ s/^\s+//;
$subjecthdr =~ s/\s+$//;
syslog("notice", "subjecthdr:$subjecthdr");

my @subject = split /\s+/,$subjecthdr;
my $cmd = lc $subject[0];
$LISTNAME = $subject[1] unless $LISTNAME;
    
if ($#subject==3 && (lc $subject[2]) eq 'confirmation') {
	my $digest = $subject[3];
	if ($digest =~ /^\"/ || $digest =~ /^\'/) {
		#strip quotes
		chop $digest;
		$digest = substr( $digest, 1 );
	}
	_processReply(_getCommand($cmd), $LISTNAME, $sender, $digest);
} else {
    if ($#subject==1 && !$LISTNAME) {
        $LISTNAME = lc $subject[1];
    }
    unless($LISTNAME) {
       $msg = "Sorry. Your maillist request could not be completed. You sent the command:\n\n  ".$subjecthdr."\n\nThat is not a valid maillist command - you did not specify a maillist name. Valid commands are:\n\nsubscribe <list-name>\nunsubscribe <list-name>";
       print $msg if DEBUG;
       _sendMail( $sender, 'Maillist error', $msg );
	   syslog("notice", "mlproxy failed to process command '$subjecthdr' because no listname provided");
       closelog();
       exit(0);
    }
    unless (MLMail::isMaillist($LISTNAME)) {
       $msg = "Sorry. Your maillist request could not be completed. You sent the command:\n\n  ".$subjecthdr."\n\n'$LISTNAME' is not a valid maillist.";
       print $msg if DEBUG;
       _sendMail( $sender, 'Maillist error', $msg );
	   syslog("notice", "mlproxy failed to process command '$cmd' because no such list:$LISTNAME");
       closelog();
       exit(0);
    }
	syslog("notice", "mlproxy processing $LISTNAME");
	unless (%info) {

	    $moderator = $info->{'moderator'};
	    $moderator = $info->{'owner'} unless ($moderator);
		$cmd = _getCommand($cmd);        
		my $digest = _generateDigest($sender, $cmd, $LISTNAME);
		my $subject = $cmd.' '.$LISTNAME.' Confirmation "'.$digest.'"';
		
		if ($cmd eq 'subscribe') {
		   my $policy = _subscriptionPolicyForSender($info, $sender);
		   print("policy:$policy\n") if DEBUG;
		   if ($policy==OWNERONLY) {
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
              	_sendMailFromTemplate("notMember", $sender, 'Maillistx error', $LISTNAME);
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
		   	} elsif ($policy!=OWNERONLY) {
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
	} else {
		$msg = "The following operation failed:\n\n".$cmd.' '.$LISTNAME."\n\nReason: Internal error:";
	  	$msg .= getErrMessage($info);
        $msg .= "\n\nPlease contact postmaster\@sfu.ca to report this problem.\n";
        print $msg if DEBUG;
        _sendMail( $sender, 'Maillist error', $msg );
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
		my $token = SOAP::Data->type(string => $main::TOKEN);
		my $listname = SOAP::Data->type(string => $list);
		my $address = SOAP::Data->type(string => $sender);
		if ($cmd eq 'subscribe') {
			$result = _subscribeViaEmail( $token, $listname, $address );
			$template = "sub2";
		} elsif ($cmd eq 'unsubscribe') {
			$result = _unsubscribeViaEmail( $token, $listname, $address );
			$template = "unsub2";
		} else {
			$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\nReason:\"".cmd."\" is not a valid command";
			_sendMail( $sender, 'Maillist error', $msg );
		}
		
		unless ($result->fault ) {
			if ($result->result()=~/^ok/) {
				_sendMailFromTemplate($template, $sender, 'Maillist Confirmation', $list);
			} else {
				$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\nReason:".substr($result->result(),3);
				_sendMail( $sender, 'Maillist error', $msg );
			}
		} else {
				$msg = "The following operation failed:\n\n".$cmd.' '.$list."\n\nReason:".$result->faultstring;
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
	my ($token, $listname, $address) = @_;
UPD: 
    for (;;) {
        eval '$main::response = $main::SERVICE -> subscribeViaEmail( $token, $listname, $address );';
        if ($@ || $main::response==0) {
            if ($@ =~ /500 Error WebObjects/ || $@ =~ /404 File Not Found/) {
                sleep 30;
                redo UPD;
            }
            my $msg = "_subscribeViaEmail failed for $token, $listname, $address:$@";
			_sendMail( "amaint\@sfu.ca", 'mlproxy error', $msg );
		}
        last;
    }
	return $main::response;
}

sub _unsubscribeViaEmail {
	my ($token, $listname, $address) = @_;
UPD: 
    for (;;) {
        eval '$main::response = $main::SERVICE -> unsubscribeViaEmail( $token, $listname, $address );';
        if ($@ || $main::response==0) {
            if ($@ =~ /500 Error WebObjects/ || $@ =~ /404 File Not Found/) {
                sleep 30;
                redo UPD;
            }
            my $msg = "_unsubscribeViaEmail failed for $token, $listname, $address:$@";
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
		$memHash{$mem->{'username'}} = 1;	
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

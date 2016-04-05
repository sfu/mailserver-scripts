package MLDtest;
use Sys::Syslog;
use Mail::Internet;
use Mail::Address;
use Mail::Send;
use URI::Escape;
use FileHandle;
use Digest::MD5;
use MIME::Base64;
use Date::Format;
use JSON;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use LOCK;
use MLMail;
use MLCache;
use MLUtils;
use SFULogMessage;
use SFUAppLog qw( log );
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( processMessage );
use vars qw($main::QUEUEDIR $main::MSG $main::ID $main::DELIVER);

use constant PIPECOMMAND => "|/usr/sbin/sendmail -oi ";
#use constant PIPECOMMAND => "|/usr/lib/sendmail -oi -odq ";
use constant MAXCMDSIZE => 16384;
use constant TOOBIG => 1;
use constant LISTID_NAMESPACE => "sfu.ca";


#
# Child process subroutines
#

sub processMessage {
    my ($dir) = @_;
    setpgrp;               # So child doesn't get ctrl-C interrupts.
    $SIG{HUP}  = 'IGNORE'; # Ignore HUP,INT,STOP,QUIT signals
    $SIG{INT}  = 'IGNORE';
    $SIG{STOP}  = 'IGNORE';
    $SIG{QUIT}  = 'IGNORE';
    $SIG{TERM}  = \&termHandler;  # Handle explicit TERM sent to child
    
    my %addresses = ();
    my $fromheader = '';
    %MLD::SEEN = ();
    %MLD::MEMBERS = ();
    my $localDomain = "sfu.ca";
    my $version  = "2.2";

    my $path = "${main::QUEUEDIR}/$dir";
    $MLD::PATH = $path;
    _stdout( "$$ processing $path" ) if $main::TEST;
    openlog "mld2", "pid", "mail";
    $MLD::LOCK = $path . ".lock";
    unless (acquire_lock( $path . ".lock" )) {
    	_stderr( "$$ error getting lock $path.lock: $!" );
		&closelog;
		return;
    }
    if (-d $path && -e "$path/addrs" && -e "$path/msg" && -e  "$path/id") {
    	$main::ID = getID($path);
        # get the message
        open $main::MSG, "$path/msg";
        my $msg  = Mail::Internet->new( $main::MSG, MailFrom => "IGNORE" );
        my $headers = $msg->head();
        
        # get the from address
        $fromheader = $headers->get("From") unless $fromheader;
	    chomp $fromheader;
        _stdout( "From $fromheader" ) if $main::TEST;
	    my $from = '';
        eval { $from = ((Mail::Address->parse($fromheader))[0])->address(); };
        _stdout( "Parsed From $from" ) if $main::TEST;
        # ignore mail with invalid From
        unless ($from) {
        	syslog("info", "Message %s has invalid From address \"$fromheader\"- ignored", $main::ID);
        	_stdout( "Message has invalid From address \"$fromheader\" - ignored" ) if $main::TEST;
            deleteMessageDirectory($path);
    		release_lock( $MLD::LOCK );
    		&closelog;
            return;
        }
        # ignore mail from mailer-daemon
        if ((lc $from) =~ /mailer-daemon\@/) {
        	syslog("info", "Message %s from mailer-daemon - ignored", $main::ID);
            deleteMessageDirectory($path);
    		release_lock( $MLD::LOCK );
    		&closelog;
            return;
        }        
    
        # remove any deprecated headers
        $headers->delete("Content-Length");
        $headers->delete("Return-Receipt-To");
        $headers->delete("Return-Path");

        # add a Received header
        my $datetime = time2str("%a, %e %b %Y %X %z (%Z)", time);
        my $hashref = $headers->header_hashref();
        unshift @{$hashref->{Received}}, "by $localDomain (mld $version); $datetime\n";
        $headers->empty();
        $headers->header_hashref($hashref);
        syslog("info", "Message %s received by mld", $main::ID);
        
        $main::sleepCounter = 0;
        getRecipients($from, $path, $msg);
        &printRecipientsHash if $main::TEST;
		if (deliver($msg, $path, $from)) {         # send the message
			_stdout( "Deleting $path" ) if $main::TEST;
			deleteMessageDirectory($path);
		} 
    } else {
      _stderr( "Bad message directory:$path" ) if -d $path;
    }
    syslog("info", "%s Releasing lock file", $main::ID);
    release_lock( $MLD::LOCK );
    &closelog;
}

sub getID {
	my $path = shift;
	open ID, "<$path/id";
	my $id = <ID>;
	close ID;
	chomp $id;
	return $id;
}

#
# Create the MLD::RECIPIENTS hash, which contains distinct recipients
# keyed by listname.
# 
sub getRecipients {
	my ($from, $path, $msg) = @_;
	my $listname = '';
	my $canonicalFrom = MLMail::canonicalAddress($from);
	unless ($canonicalFrom) {
		if (MLMail::hasLocalDomain($from)) {
		    syslog("info", "%s Warning! Message has bogus local From address %s.", $main::ID, $from );
			$canonicalFrom = $from;
		}
	}
	_stdout( "getRecipients: canonicalFrom: $canonicalFrom" ) if $main::TEST;
    # warn about listnames as from address
    if (MLMail::isMaillist($canonicalFrom)) {
		syslog("warning", "%s Message has From address which is a maillist: %s.", $main::ID, $canonicalFrom );
        _stdout( "Message has From address which is a maillist: $canonicalFrom" ) if $main::TEST;
    }
    
	$MLD::COPYONSEND = 0;                    # Initialize the copyonsend flag
	
	#
	# If the recipients have been cached due to a terminated mld process, get
	# them from the cache, then delete the cache.
	# Otherwise, build the recipients list normally.
	#
	if (-e "$path/recipients" && loadRecipientsFromCache("$path/recipients")) {
	   deleteRecipientsCache("$path/recipients");
	} else {
        open ADDRS, "$path/addrs";
        my @addrs = <ADDRS>;
        foreach $listname (@addrs) {
            %MLD::REJECTEDLISTS = ();
            %MLD::BOUNCES = ();
            %MLD::SIZEREJECTEDLISTS = ();
            %MLD::SIZEBOUNCES = ();
            %MLD::LISTID = ();
            chomp $listname;
    		my $mlcache = new MLCache($listname, $main::MLROOT);
    		unless( $mlcache) {
				syslog("err", "%s delivery to %s failed because list config is  not available.", $main::ID, $listname );
				_sendMail( "amaint@sfu.ca", "Error - delivery to \"$listname\" failed", "Delivery to \"$listname\" failed because cache files are not available.", "owner-$listname\@sfu.ca" );
                &cleanexit;
    		}
    		
    		# Set the current list-id header
    		$MLD::CURRENT_LISTID = "<$listname.".LISTID_NAMESPACE.">";
    		
            getlistmembers( $canonicalFrom, $mlcache, $msg );
                        
            # Send rejection message back for any lists that the user cannot send to
            if ($MLD::REJECTEDLISTS{$listname}) {
                sendRejectionMsg( $from, $listname, "\"$from\" is not on the allowed sender list.", $msg );
            } elsif ($MLD::SIZEREJECTEDLISTS{$listname}) {
				my $reason = "Message exceeds maximum size accepted by the list: \nMax size: ".$mlcache->maximumMessageSize()."\nMsg size: ".length($msg->as_string());
                sendRejectionMsg( $from, $listname, $reason, $msg );
            } else {
				if (keys %MLD::REJECTEDLISTS) {
					sendPartialDeliveryMsg( $from, $listname, "Warning - partial delivery to $listname", $msg );
				} 
				if (keys %MLD::SIZEREJECTEDLISTS) {
					sendSizePartialDeliveryMsg( $from, $listname, "Warning - partial delivery to $listname", $msg );
				} 
            }
     
            foreach $list (keys %MLD::BOUNCES) {
                _bounceToModerator( $from, $list, $msg );
            }   
            foreach $list (keys %MLD::SIZEBOUNCES) {
                _bounceToModerator( $from, $list, $msg, TOOBIG );
            }   
        }
        %MLD::RECIPIENTS = ();
        delete $MLD::MEMBERS{$canonicalFrom} unless $MLD::COPYONSEND;
        foreach $addr (keys %MLD::MEMBERS) {
            my $listname = $MLD::MEMBERS{$addr};
            if (defined $MLD::RECIPIENTS{$listname}) {
                push @{ $MLD::RECIPIENTS{$listname} }, $addr;
            } else {
                $MLD::RECIPIENTS{$listname} = [ $addr ];
            }
        }
	}
}

#
# Get the members of a list and all its embedded lists and
# store them in the %MLD::MEMBERS hash.
#
sub getlistmembers {
    my ($sender, $mlcache, $msg) = @_;
    my ($address, $content);
    my $listname = $mlcache->name();
    $MLD::SEEN{ $listname } = 1;
    _stdout("getlistmembers for ".$mlcache->name() ) if $main::TEST;
	my $id = $main::ID;
	my $headers = $msg->head();
    my $subject = $headers->get('subject');
	$subject =~ s/[[:^ascii:]]/\?/g;
    #
    # Check if sender is allowed to send to this list
    #
	my $allowed = $mlcache->allowedToSend( $sender );
	SWITCH: {
		$allowed=~/SEND/   && do {
						if ($mlcache->deliverySuspended()) {
							syslog("info", "%s %s is not allowed to send to %s - delivery is suspend. Sending rejection message.", $id, $sender, $listname );
							sendRejectionMsg( $sender, $listname, "Delivery of mail to list is currently suspended.", $msg );
							$sender =~ s/[[:^ascii:]]/\?/g;
						    my $detail = _detailJson($id, $sender, $subject,  
						        "Reason: Delivery of mail to list $listname is currently suspended");
						    _appLog("message rejected", $detail,  
						        ["$listname","$sender", "$id", "#mldelivery"]);
							return;
						}
		                syslog("info", "%s %s sending to %s.", $id, $sender, $listname );
						last SWITCH;
					};
								
		$allowed=~/TRASH/  && do {
						syslog("info", "%s %s is not allowed to send to %s. Trashing message.", $id, $sender, $listname );
						$sender =~ s/[[:^ascii:]]/\?/g;
						my $detail = _detailJson($id, $sender, $subject,  
						        "Reason: $sender is not allowed to send to $listname");
						_appLog("message trashed", $detail,  
						        ["$listname","$sender", "$id", "#mldelivery"]);
						return;
					};
								
		$allowed=~/REJCT/  && do {
						syslog("info", "%s %s is not allowed to send to %s. Sending rejection message.", $id, $sender, $listname );
						$sender =~ s/[[:^ascii:]]/\?/g;
						my $detail = _detailJson($id, $sender, $subject,  
						    "Reason: $sender is not allowed to send to $listname");
						_appLog("message rejected", $detail,  
						        ["$listname","$sender", "$id", "#mldelivery"]);
                        $MLD::REJECTEDLISTS{$listname}=1;
						return;
					};
								
		$allowed=~/BOUNC/  && do {
                        #my($junk,$moderator) = split /\s+/,$allowed;
                        $MLD::BOUNCES{$listname}=$mlcache->effectiveModerator();
						syslog("info", "%s %s is not allowed to send to %s. Bouncing to moderator %s.", $id, $sender, $listname, $MLD::BOUNCES{$listname} );
						$sender =~ s/[[:^ascii:]]/\?/g;
						my $detail = _detailJson($id, $sender, $subject,  
						    "Reason: $sender is not allowed to send to $listname - bouncing to moderator");
						_appLog("message bounced", $detail,  
						    ["$listname","$sender", "$id", "#mldelivery"]);
						return;
					};
		syslog("warning", "%s Unrecognized mail handling code \"%s\" when sending message to %s from sender %s.", $id, $listname, $sender );
		return;
	}
	#
	# Check if message should be rejected due to size
	#
	my $msgSizeHandling = $mlcache->mailSizeHandling( $sender, $msg );
	syslog("info", "%s msgSizeHandling: %s", $main::ID, $msgSizeHandling);

	SWITCH2: {								
		$msgSizeHandling=~/SEND/   && do {
						last SWITCH2;
					};
								
		$msgSizeHandling=~/REJCT/  && do {
						syslog("info", "%s Message from %s exceeds max size for %s. Sending rejection message.", $main::ID, $sender, $listname );
                        $MLD::SIZEREJECTEDLISTS{$listname}=1;
						return;
					};
								
		$msgSizeHandling=~/BOUNC/  && do {
                        $MLD::SIZEBOUNCES{$listname}=$mlcache->effectiveModerator();
						syslog("info", "%s Message from %s exceeds max size for %s. Bouncing to moderator %s.", $main::ID, $sender, $listname, $MLD::SIZEBOUNCES{$listname} );
						return;
					};
	}
	
	# Set the copyonsend flag if it is on for this list, and it hasn't
	# already been set.
	# The sender will get a copy of the message if this flag is set on this 
	# or any embedded list
    my $memref = $mlcache->members();
    if ($memref->{$sender}{copyonsend} == 1 && !$MLD::COPYONSEND) {
		syslog("info", "%s Adding sender %s to delivery list for %s because copyonsend flag = true.", $main::ID, $sender, $listname );
        _stdout( "Adding sender $sender to delivery list for $listname because copyonsend flag = true." ) if $main::TEST;
        $MLD::COPYONSEND=1;
        $MLD::MEMBERS{$sender} = $listname;
    }

    # Set the List-Id value to the List-Id of the current top-level list,
    # so that messages sent via nested lists will display the top-level list
    # as the List-Id.
    # This behaviour is required by RFC2919 (section 7). 
    if (!defined $MLD::LISTID{$listname}) {
        $MLD::LISTID{$listname} = $MLD::CURRENT_LISTID;
    }
    
    # Get the members of the list.
    # If there are no recipients for this list, log it and return.
    $content = $mlcache->deliveryList();
    print "deliveryLIst: $content\n" if $main::TEST;
    my @addresses = split "\n", $content;
    if (noRecipientsForList( $listname, $sender, @addresses )) {
        _logNoRecipients( $listname, $sender, $subject );
        return;
    }
        
    #
    # Add each address to the MEMBERS hash. 
    # Do the immediate addresses first, and save embedded maillists for later 
    #
    my @maillists = ();
    foreach $address (split "\n", $content) {
        chomp $address;
        if ($address =~ /^\*/) {
            push @maillists, $address;
        } else {
            $MLD::MEMBERS{$address} = $listname unless exists $MLD::MEMBERS{$address};
            _stdout($address."=".$MLD::MEMBERS{$address});
        }
    }
    #
    # Now recursively process the addresses which are maillists.
    #
    foreach $address (@maillists) {
        my $ml = substr $address, 1;
        next if $MLD::SEEN{$ml};
        my $mlc = new MLCache($ml, $main::MLROOT);
        unless( $mlc) {
            syslog("err", "%s delivery to %s failed because cache files are not available.", $main::ID, $ml );
            _sendMail( "amaint@sfu.ca", "Error - delivery to \"$ml\" failed", "Delivery to \"$ml\" failed because list config is not available.", "owner-$listname\@sfu.ca" );
            &cleanexit;
        }
        getlistmembers($sender, $mlc, $msg) if $mlc;
    } 
}

#
# Return true if there are no members with delivery turned on, 
#             and the sender is not copied as a result of this list.
#
sub noRecipientsForList {
    my ( $listname, $sender, @addresses ) = @_;
    if ($#addresses == -1 && $MLD::MEMBERS{$sender} ne $listname) { return 1; }
    return 0;
}

#
# Send a message to the recipients in %MLD::RECIPIENTS
#
sub deliver {
    my ($msg, $path, $from) = @_;
    my $result = 1;
    my $success = 1;
    my @keys = keys %MLD::RECIPIENTS;
    if (-1 == $#keys) {
        syslog("info", "%s No recipients. Ignoring.", $main::ID );
        _stdout( "No recipients. Ignoring." ) if $main::TEST;
        return 1;
    }
	foreach $list (keys %MLD::RECIPIENTS) {
		$success = deliverToList( $list, $msg, $MLD::RECIPIENTS{$list}, $from );
        delete $MLD::RECIPIENTS{$list} if $success;
	    $result &= $success;
	    sleep 1;
	}
	return $result;
}

#
# Do the actual delivery. sendmail commands are issued for batches 
# of 255 addresses at a time. (This should actually be much shorter
# than the max command line length)
#
sub deliverToList {
    my ($list, $msg, $membersRef, $from) = @_;
    my @members = @{ $membersRef };
    my $recipient;
    my $rcptCounter = 0;
    my $headers = $msg->head();
    my $subject = $headers->get('subject');
	$subject =~ s/[[:^ascii:]]/\?/g;

    
    _stdout( "DeliverToList:$list" ) if $main::TEST;
    my $mlc = new MLCache($list);
    
    # Remove any existing List-Id header and add the correct one for this list
    $msg->delete("List-Id");
    $msg->add("List-Id", $MLD::LISTID{$list} );
    
    # Add a local header to indicate the actual delivering list.
    $msg->delete("X-Sfu-Delivering-List-Id");
    $msg->add("X-Sfu-Delivering-List-Id", "<$list.".LISTID_NAMESPACE.">" );
    
    # Remove existing RFC2369 headers and add ones for this list.
    $msg->delete("List-Help");
    $msg->delete("List-Owner");
    $msg->delete("List-Unsubscribe");
    $msg->delete("List-Subscribe");
    $msg->add("List-Help", "<mailto:$list-request\@sfu.ca?subject=help> (List Instructions)" );
    $msg->add("List-Owner", "<mailto:owner-$list\@sfu.ca>" );
    # Only add the unsubscribe header for a regular maillist.
    # Only add the subscribe header if subscribe via email is allowed.
    if ($mlc->{type}==0) {
        $msg->add("List-Unsubscribe", "<mailto:$list-request\@sfu.ca?subject=unsubscribe>" );
        if ($mlc->{allowedToSubscribeByEmail}) {
            $msg->add("List-Subscribe", "<mailto:$list-request\@sfu.ca?subject=subscribe>" );
        }
    }

    $MLD::commandBuf = PIPECOMMAND;
    $MLD::commandBuf.= "-f \"owner-$list\"";
    $MLD::commandPrefixLength = length($MLD::commandBuf);
    my @recipients = orderAddresses(@members);
    if (-1 == $#recipients) {
        syslog("info", "%s No recipients for $list. Ignoring.", $main::ID );
        _stdout( "No recipients for $list. Ignoring." ) if $main::TEST;
        my $id = $main::ID;
        my $cleanfrom = $from;
        $cleanfrom =~ s/[[:^ascii:]]/\?/g;
        my $detail = _detailJson($id, $cleanfrom, $subject, "No recipients for list");
        _appLog("message ignored", $detail, ["$list","$cleanfrom", "$id", "#mldelivery"]);
        return 1;
    }
    
    foreach $recipient (@recipients) {
    	if ($recipient =~ /[][><:;"\\\s]/) {
            syslog("info", "%s bad chars in recipient:%s  Ignoring.", $main::ID, $recipient );
            next
    	}
        if (!roomForRecipient($recipient) || $rcptCounter>254) {
            eval { sendToSendmail($msg); };         # cmd buf is full; send msg
            if ($@) {
                syslog("err", "%s eval failed for command:%s", $main::ID, $MLD::commandBuf);
                _stderr( "${main::ID} eval failed for command:${MLD::commandBuf}" );
                _stderr( $@ );
                return 0;
            } else {
                my $id = $main::ID;
                my $cleanfrom = $from;
                $cleanfrom =~ s/[[:^ascii:]]/\?/g;
				my $detail = _detailJson($id, $cleanfrom, $subject,  
						"Recipients: ".substr($MLD::commandBuf,
						$MLD::commandPrefixLength));
				_appLog("message delivered", $detail,  
                        ["$list","$cleanfrom", "$id", "#mldelivery"]);
            }
            $MLD::commandBuf = PIPECOMMAND;         # start a new command
            $MLD::commandBuf.= "-f \"owner-$list\"";
            $rcptCounter = 0;
        }
        if ($recipient =~ /^([-\w.+'&@]+)$/) {
            $recipient = $1;                        # untaint recipient
            if ($recipient =~ /['&]/) {             # and wrap in double-quotes 
            	$recipient = "\"$recipient\"";      # if necessary
            }
        } else {
            _stderr( "Ignoring recipient after taint check:$recipient" ) if $main::TEST;
            my $hex = unpack "H*",$recipient;
            _stderr( "Hex:$hex" ) if $main::TEST;
            syslog("warning", "%s bad data in recipient:%s (0x%s). Ignoring.", $main::ID, $recipient, $hex );
            $recipient = '';
        }
        $MLD::commandBuf .= " $recipient" if $recipient;   # add recipient
        $rcptCounter++;
    }
    eval { sendToSendmail($msg) if (length($MLD::commandBuf) > length(PIPECOMMAND)+length("-f \"owner-$list\"")); };
    if ($@) {
        syslog("err", "%s eval failed for command:%s", $main::ID, $MLD::commandBuf);
        _stderr( "${main::ID} eval failed for command:${MLD::commandBuf}" );
        _stderr( $@ );
        return 0;
    } else {
        my $id = $main::ID;
        my $cleanfrom = $from;
        $cleanfrom =~ s/[[:^ascii:]]/\?/g;
		my $detail = _detailJson($id, $cleanfrom, $subject,  
			"Recipients: ".substr($MLD::commandBuf, $MLD::commandPrefixLength));
		_appLog("message delivered", $detail,  
                ["$list","$cleanfrom", "$id", "#mldelivery"]);
    }
    return 1;
}        

#
# Order addresses by domain name, so that all addresses for a domain
# appear together. SFU addresses are first.
#
sub orderAddresses() {
    my @addresses = @_;
    my $recipient;
    my %recipients;
    my @recipients = ();
    my $domain = "";
	
    foreach $recipient (@addresses) {
        $recipient =~ /^.*?@(.*)/;
        $domain = $1 if index($recipient,"@")>-1;
        my $key = $domain."\$".$recipient;
        $recipients{$key} = $recipient;
        $domain = "";
    }
    
    foreach $key (sort keys %recipients) {
        push @recipients, $recipients{$key};
    }
    
    return @recipients;
}

sub sendToSendmail {
    my ($msg) = @_;

    if ($main::TEST) {
        _stdout( "Sendmail command:" );
        _stdout( $MLD::commandBuf );
       $msg->print();
    } 
    if ($main::DELIVER) {
        syslog("info", "%s sendmail command: %s", $main::ID, $MLD::commandBuf);
        my $sendmail = new FileHandle;
        open($sendmail, $MLD::commandBuf)
            or do { 
            	syslog("info", "%s sendmail command failed:%s", $main::ID, $MLD::commandBuf);
            	_stdout("sendmail command failed:".$MLD::commandBuf) if $main::TEST;
            	return;
            };
        $msg->print($sendmail);
        close($sendmail);
    }
}

sub roomForRecipient {
    my ($recipient) = @_;
    
    # Need space for existing command + space char + recipient + two 
    # extra chars in case we have to wrap the recipient in double quotes
	return 1 if ((length($MLD::commandBuf) + 1 + length($recipient) + 2) < MAXCMDSIZE);
    return 0;
}


sub deleteMessageDirectory {
    my ($path) = @_;
    syslog("info", "%s Deleting message directory", $main::ID);
    _stdout( "unlinking $path/addrs" ) if $main::TEST;
    unlink "$path/addrs";
    _stdout( "unlinking $path/id" ) if $main::TEST;
    unlink "$path/id";
    _stdout( "unlinking $path/msg" ) if $main::TEST;
    unlink "$path/msg";
    _stdout( "rmdiring $path" ) if $main::TEST;
    unlink "$path/recipients.dir" if -e "$path/recipients.dir";
    unlink "$path/recipients.pag" if -e "$path/recipients.pag";
    rmdir($path) or syslog("err","%s Couldn't delete message directory %s:%s", $main::ID, $path, $! );
    #rmdir($path) or die("Couldn't delete message directory $path: $!");
}


#
# Utility subroutines
#

sub termHandler {
    my ($signal) = @_;
    my %cache;
    my $list;
    syslog("err","%s termHandler: Child got %s signal", $main::ID, $signal);    
    _stdout( "Child got $signal signal" ) if $main::TEST;
    $SIG{TERM}  = 'IGNORE' if $signal eq  "TERM";
    if (-e $MLD::PATH && keys %MLD::RECIPIENTS) {
        writeRecipientsToCache("${MLD::PATH}/recipients");
	}
    if (-e $MLD::LOCK) {
      #_stdout( "$$ unlinking ${MLD::LOCK}" ) if $main::TEST;
      syslog("info","%s %s releasing lock file %s", $$, $main::ID, $MLD::LOCK);    
      release_lock( $MLD::LOCK );
    }
    &closelog;
    $MLD::TERM = 1;    # See getFromURL for explanation.
    die "Child $$ interrupted!";
}

sub loadRecipientsFromCache {
    my ($filename) = @_;
    my %recipients = ();
    my $addr = '';
    my $listname = '';
    my $key = '';
    %MLD::RECIPIENTS = ();
    _stdout("$$ loading recipients for ${main::ID} from saved cache $filename") if $main::TEST;
    if (open(CACHE, "$filename")) { 
        while (<CACHE>) {
            chomp;
            ($addr,$listname) = split /\t/;
            if (defined $MLD::RECIPIENTS{$listname}) {
                push @{ $MLD::RECIPIENTS{$listname} }, $addr;
            } else {
                $MLD::RECIPIENTS{$listname} = [ $addr ];
            }
        }
    } else {
        _stderr( "$$ can't open cache file for read: $!" );
        return 0;
    }
    return 1;
}

sub writeRecipientsToCache {
    my ($filename) = @_;
    my $listname = '';
    my $recipient = '';
    my @recipients = ();
    _stdout("$$ saving recipients for ${main::ID} in $filename") if $main::TEST;
    if (open(CACHE, ">$filename")) { 
        foreach $listname (keys %MLD::RECIPIENTS) {
            my @recipients = @{ $MLD::RECIPIENTS{$listname} };
            foreach $recipient (@recipients) {
                print CACHE "$recipient\t$listname\n";
            }
        }
        close CACHE;
    } else {
        _stderr( "$$ can't open cache file for write: $!" );
        &printRecipientsHash;
    }
}

sub deleteRecipientsCache {
    my ($path) = @_;
    unlink $path;
}

sub sendRejectionMsg {
    my ($to, $listname, $reason, $msg) = @_;
    my $canonicalTo = MLMail::canonicalAddress($to);
    my %xheaders = ();
    if (MLMail::isMaillist($canonicalTo)) {
    	syslog("err", "%s will not return rejection message to a from address which is a maillist: %s.", $main::ID, $canonicalTo );
        _stdout( "Warning! Will not return rejection message to a from address which is a maillist: $canonicalTo." ) if $main::TEST;
    	return;
    }

    my $body = "Your message to \"$listname\" was rejected for the following reason:\n" 
              ."$reason\n\n"
              ."Please email owner-$listname\@sfu.ca if you have any questions.\n"
              ."The original message follows:\n\n  ";
    $body .= join "\n  ",split /\n/,$msg->as_string();
    $xheaders{"SFU-Rejection"} = $reason;
    _sendExtras( $to, "Message to \"$listname\" rejected", $body, "owner-$listname\@sfu.ca", %xheaders );
}

sub sendPartialDeliveryMsg {
    my ($to, $listname, $reason, $msg) = @_;
    my $canonicalTo = MLMail::canonicalAddress($to);
    if (MLMail::isMaillist($canonicalTo)) {
    	syslog("err", "%s will not return partial delivery message to a from address which is a maillist: %s.", $main::ID, $canonicalTo );
        _stdout( "Warning! Will not return partial delivery message to a from address which is a maillist: $canonicalTo." ) if $main::TEST;
    	return;
    }
    
    my $body = "Your message to \"$listname\" was only partially delivered.\n"
              ."The following members of \"$listname\" are maillists\n"
              ."to which you are not authorized to send:\n\n";
    foreach $list (keys %MLD::REJECTEDLISTS) {
        $body .= "$list\n";
    }
    $body .= "\nPlease email owner-$listname\@sfu.ca if you have any questions.\n";
    $body .= "The original message follows:\n\n  ";
    $body .= join "\n  ",split /\n/,$msg->as_string();
    _sendMail( $to, "Warning - partial delivery to \"$listname\"", $body, "owner-$listname\@sfu.ca" );
}

sub sendSizePartialDeliveryMsg {
    my ($to, $listname, $reason, $msg) = @_;
    my $canonicalTo = MLMail::canonicalAddress($to);
    if (MLMail::isMaillist($canonicalTo)) {
    	syslog("err", "%s will not return partial delivery message to a from address which is a maillist: %s.", $main::ID, $canonicalTo );
        _stdout( "Warning! Will not return partial delivery message to a from address which is a maillist: $canonicalTo." ) if $main::TEST;
    	return;
    }
    
    my $body = "Your message to \"$listname\" was only partially delivered \n"
              ."because it exceeded the size limit of some of the embedded maillists.\n"
              ."The following members of \"$listname\" are maillists\n"
              ."to which your message was not sent:\n\n";
    foreach $list (keys %MLD::SIZEREJECTEDLISTS) {
        $body .= "$list\n";
    }
    $body .= "\nPlease email owner-$listname\@sfu.ca if you have any questions.\n";
    $body .= "The original message follows:\n\n  ";
    $body .= join "\n  ",split /\n/,$msg->as_string();
    _sendMail( $to, "Warning - partial delivery to \"$listname\"", $body, "owner-$listname\@sfu.ca" );
}

sub _bounceToModerator {
    my ($sender, $listname, $msg, $toobigFlag) = @_;
    my $moderator = $MLD::BOUNCES{$listname};
    my $body = join "",@{$msg->body()};
    my $subject = "Bounce to moderator of \"$listname\": ";
    if ($toobigFlag) {
    	$subject .= "Message too large";
    } else {
    	$subject .= "sender \"$sender\" not authorized";
    } 
    _sendMail( $moderator ? $moderator : "owner-$listname", $subject, $body, $sender );
}

sub cleanexit {
    closelog();
    exit(0);
}

sub printRecipientsHash {
    _stdout( "child $$ Final delivery list:" );
    foreach $list (sort keys %MLD::RECIPIENTS) {
      _stdout( "$list" );
      _stdout( "-------------------" );
      foreach $member (sort @{ $MLD::RECIPIENTS{$list} }) {
        _stdout( "$member" );
      }
    }
}

sub _logNoRecipients {
    my ($list, $from, $subject) = @_;
    my $id = $main::ID;
    my $cleanfrom = $from;
    $cleanfrom =~ s/[[:^ascii:]]/\?/g;
    my $detail = _detailJson($id, $cleanfrom, $subject, "No recipients for list");
    _appLog("message ignored", $detail, ["$list","$cleanfrom", "$id", "#mldelivery"]);
    syslog("warning","Warning: %s message from %s, no recipients for list %s, discarding message",$id,$from,$list);
}

sub _detailJson {
    my ($msgId, $from, $subject, $info) = @_;
    my %headers = ();
    $headers{from} = $from;
    $headers{subject} = $subject;
    my %detail = ();
    $detail{msgId} = $msgId;
    $detail{headers} = \%headers;
    $detail{info} = $info;
    return encode_json \%detail;
}

sub _appLog {
    my ($event, $detail, $tags) = @_;
    my $msg = new SFULogMessage();
    $msg->setEvent($event);
    $msg->setDetail($detail);
    $msg->setAppName("mld");
    $msg->setTags($tags);
    syslog("info", "%s Sending applog message", $main::ID);
    my $APPLOG = new SFUAppLog();
    eval { $APPLOG->log('/queue/ICAT.log',$msg); };
    if ($@) {
        syslog("err", "%s eval failed for call to APPLOG log", $main::ID);
        syslog("err", "%s APPLOG result: %s", $main::ID, $@);
        _stderr( "${main::ID} eval failed for call to APPLOG log" );
        _stderr( $@ );
    }
}

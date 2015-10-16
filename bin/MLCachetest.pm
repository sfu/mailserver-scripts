package MLCachetest;

require Exporter;
@ISA    = qw(Exporter);
use lib "/opt/mail/maillist2/bin";
use LOCK;
use MLMail;
use MLUtils;
use lib "/opt/mail/maillist2/lib";
use MLUpdt;

# member types
use constant MAILLIST => 2;
use constant LOCAL    => 3;
use constant EXTERN   => 4;

# allow/deny types
use constant MLMATCH  => 3;
use constant WILDCARD => 4;
use constant REGEX    => 5;

# allowedToSend results
use constant SEND   => 'SEND';
use constant BOUNCE => 'BOUNC';
use constant REJECT => 'REJCT';
use constant TRASH  => 'TRASH';


sub new {
	my $class = shift;
	my $name  = shift;
	my $root  = shift;
	my $self = {};
	bless $self, $class;
	$root = $main::MLROOT unless $root;
	$root = "/opt/mail/maillist2" unless $root;
	_refreshCache($name);
	unless (-e "$root/files/$name") {
		_stderr("$root/files/$name/maillist doesn't exist!") if $main::TEST;
		return undef;
	}
	$self->{root} = $root;
	_stdout("opening "."$root/files/$name/maillist") if $main::TEST;
	dbmopen %CACHE, "$root/files/$name/maillist", 0660
		or die "Can't dbmopen $root/files/$name/maillist: $!\n";
	my @keys = keys %CACHE;
	@$self{@keys} = values %CACHE;
	dbmclose %CACHE;
	return $self;
}

sub name {
	my $self = shift;
	return $self->{name};
}

sub owner {
	my $self = shift;
	return $self->{owner};
}

sub members {
	my $self = shift;
	unless ($self->{members}) {
		my %members = ();
		my $name = $self->{name};
		my @keys = qw( type manager deliver copyonsend ); 
		return undef unless -e $self->{root}."/files/$name/members";
		open( MEMBERS, $self->{root}."/files/$name/members" ) 
			or die "Can't open ".$self->{root}."/files/$name/members: $!\n";
		while (<MEMBERS>) {
			chomp;
			my @values = split /\t/;
			my $address = shift @values;
			if ($values[0] == 4) {  # if external address, remove any comments.
				my $canon = MLMail::canonicalAddress( $address );
				$address = $canon if $canon;
			}
            if ($members{$address}) {
                # The canonical address is already in the list. This can
                # happen if there is an foo@sfu.ca and foo@cs.sfu.ca address 
                # in the list. 
                # In this case just set the deliver value to true if 
                # either of the values is true.
                # Note, this won't be required after these old
                # addresses get removed.      RAU 2011/10/20
                _stdout("$address deliver is: ".$values[2]) if $main::TEST;
                $members->{$address}{deliver} = 
                            $members->{$address}{deliver} || $values[2];
            } else {
			    for ($i=0; $i<4; $i++) {
				    $members{$address}{$keys[$i]} = $values[$i];
			    }
			}
		}
		close MEMBERS;
		$self->{members} = \%members;
	}
	return $self->{members};
}

sub allowed {
	my $self = shift;
	unless ($self->{allowed}) {
		my %members = ();
		my $name = $self->{name};
		my @keys = qw( type  ); 
		return undef unless -e $self->{root}."/files/$name/allow";
		open( MEMBERS, $self->{root}."/files/$name/allow" ) 
			or die "Can't open ".$self->{root}."/files/$name/allow: $!\n";
		while (<MEMBERS>) {
			chomp;
			my @values = split /\t/;
			my $address = shift @values;
			my $type = shift @values;
			my $displayAddress = shift @values;
			$address = $displayAddress if $address eq '*static*';
			$members{$address} = $type;
		}
		close MEMBERS;
		$self->{allowed} = \%members;
	}
	return $self->{allowed};
}

sub denied {
	my $self = shift;
	unless ($self->{denied}) {
		my %members = ();
		my $name = $self->{name};
		my @keys = qw( type  ); 
		return undef unless -e $self->{root}."/files/$name/deny";
		open( MEMBERS, $self->{root}."/files/$name/deny" ) 
			or die "Can't open ".$self->{root}."/files/$name/deny: $!\n";
		while (<MEMBERS>) {
			chomp;
			my @values = split /\t/;
			my $address = shift @values;
			my $type = shift @values;
			my $displayAddress = shift @values;
			$address = $displayAddress if $address eq '*static*';
			$members{$address} = $type;
		}
		close MEMBERS;
		$self->{denied} = \%members;
	}
	return $self->{denied};
}

sub deliveryList {
	my $self = shift;
	unless ($self->{deliveryList}) {
		$self->{deliveryList} = "";
		my $name = $self->{name};
		my $baseDir = $self->{root}."/files/$name";
		unlink "$baseDir/deliveryList" if $self->hasStaleDeliveryList();
		
		if (open( CACHE, "<$baseDir/deliveryList" )) {
			while (<CACHE>) {
				$self->{deliveryList} .= $_;
			}
			close CACHE;
			return $self->{deliveryList};
		}
		my $members = $self->members();
		foreach $address (keys %{$members}) {
			if ($members->{$address}{deliver}) {
				if ($members->{$address}{type} == MAILLIST) {
					$self->{deliveryList} .= "*$address\n"
				} elsif ($members->{$address}{type} == EXTERN) {
					$self->{deliveryList} .= "$address\n"
				} else {
					$self->{deliveryList} .= "$address\n" if MLMail::validateUsername($address);
				}
			}
		}
		if (open( CACHE, ">".$self->{root}."/files/$name/deliveryList" )) {
			print CACHE $self->{deliveryList};
			close CACHE;
		}
	}
	return $self->{deliveryList};
}

sub allowedToSend {
	my $self = shift;
	my $sender = shift;
	my $result = '';
	my %seen = ();
	my $canonicalSender = MLMail::canonicalAddress($sender);
	_stdout( "allowedToSend:canonicalSender: $canonicalSender" ) if $main::TEST;
	_stdout( "allowedToSend:name: ".$self->{name} ) if $main::TEST;
	unless ($canonicalSender) {
		if (MLMail::hasLocalDomain($sender)) {
			$canonicalSender = MLMail::stripDomain($sender);
		} else {
			return TRASH;
		}
	}
	
	# Special handling if sender is maillist
	if (MLMail::isMaillist($canonicalSender)) {
		_stdout( "allowedToSend: $canonicalSender is a maillist" ) if $main::TEST;
		if ($self->canonicalAllowedToSend($canonicalSender)) {
			return SEND;
		} else {
			return $self->mailHandlingCodeForUnauthSender($canonicalSender,1);
		}
	}

	if ($self->canonicalAllowedToSend($canonicalSender)) {
		return SEND;
	} elsif ($self->equivalentAllowedToSend($canonicalSender)) {
		return SEND;
	} else {
		if ($self->isMemberOfExpandedList($canonicalSender, \%seen)) {
			_stdout( "allowedToSend: $canonicalSender is member of expanded list" ) if $main::TEST;
			$result = $self->mailHandlingCodeForUnauthSender($canonicalSender,1);
		} else {
			_stdout( "allowedToSend: $canonicalSender is NOT member of expanded list" ) if $main::TEST;
			$result = $self->mailHandlingCodeForUnauthSender($canonicalSender,0);
# 			if (MLMail::hasNoDomain($canonicalSender)) {
# 				# local address
# 				if ($self->{nonmemberHandlingCode} ne BOUNCE && 
# 							(MLMail::validateUsername($canonicalSender) ||
# 							 MLMail::isMaillist($canonicalSender))) {
# 					$result = REJECT;
# 				} else {
# 					$result = $self->{nonmemberHandlingCode};
# 				}
# 			} else {
# 				$result = $self->mailHandlingCodeForUnauthSender($canonicalSender,0);
# 			}
		}
	}
	return $result;
}

#
# Determine whether a canonical address is allowed to send to the list.
#
sub canonicalAllowedToSend {
	my $self = shift;
	my $sender = shift;
	my %seen = ();
	my @SYSADMINS = qw( postmast postmaster robert amaint vanepp hillman frances mstanger );
	
	if (MLMail::hasNoDomain($sender)) {
		# local
		_stdout( "canonicalAllowedToSend:sender: ".$sender ) if $main::TEST;
		if (MLMail::isMaillist($sender)) {
			return $self->matchesRegexInAllowList($sender);
		} 
		return 1 if $sender eq $self->{owner};
		return 1 if grep { $sender eq $_ } @SYSADMINS;
		return 1 if $self->isManager($sender);
		my $canSendByDefault = !$self->{localSenderPolicy} || 
			($self->{localDefaultAllowedToSend} && $self->isMemberOfExpandedList($sender, \%seen));
		if ($canSendByDefault) {
			return $self->allowLevel($sender) >= $self->denyLevel($sender);
		} else {
			my $allowLevel = $self->allowLevel($sender);
			return $allowLevel > 0 && ($allowLevel > $self->denyLevel($sender));
		}
	} else {
		# external
		my $canSendByDefault = !$self->{externalSenderPolicy} || 
			($self->{externalDefaultAllowedToSend} && $self->isMemberOfExpandedList($sender, \%seen));
		if ($canSendByDefault) {
			return $self->allowLevel($sender) >= $self->denyLevel($sender);
		} else {
			my $allowLevel = $self->allowLevel($sender);
			return $allowLevel > 0 && ($allowLevel > $self->denyLevel($sender));
		}
	}
}

#
# Determine whether an address equivalent to a supplied one is allowed to send
#
sub equivalentAllowedToSend {
	my $self = shift;
	my $sender = shift;
	my $equiv = '';
	my @equivs = MLMail::equivalentAddresses($sender);
	foreach $equiv (@equivs) {
	  next unless $equiv;
	  return 1 if $self->canonicalAllowedToSend($equiv);
	}
	return 0;
}

#
# Check if a supplied CANONICAL ADDRESS is a member of the fully expanded list.
# The second arg is a ref to a hash in which seen maillists will be stored,
# to prevent loops.
#
sub isMemberOfExpandedList {
	my $self = shift;
	my ($address, $seen) = @_;
	my $member = '';
	my $listname = '';
	my $result = 0;
	
	return $self->{moel}{$address} if defined($self->{moel}{$address});
	$seen->{$self->{name}} = 1;
	my $members = $self->members();
	return 1 if $members->{$address}; # check if immediate member
	                                  # (This is fast so don't bother cacheing)
	# address not found in the immediate list.
	# Go through embedded lists.
	#
	foreach $member (keys %{$members}) {
		if ($members->{$member}{type} == MAILLIST) {
			_stdout( "isMemberOfExpandedList: $member is a maillist" ) if $main::TEST;
			next if $seen->{$member};
			my $mlc = new MLCache($member);
			next unless $mlc;
			$result = 1 if $mlc->isMemberOfExpandedList($address,$seen);
		} 
	}
	$self->{moel}{$address} = $result;
	return $result;
}

sub isManager {
	my $self = shift;
	my $address = shift;
	my $member = '';
	my $members = $self->members();
	
	return 1 if defined($members->{$address}) && $members->{$address}{manager};
	#
	# address not found in the immediate list.
	# Check embedded lists that have the manager attribute set.
	#
	my %seen = ();
	$seen{$self->{name}} = 1;
	foreach $member (keys %{$members}) {
		if ($members->{$member}{type} == MAILLIST && $members->{$member}{manager}) {
			my $mlc = new MLCache($member);
			return 1 if $mlc->isMemberOfExpandedList($address,$seen);
		} 
	}
	# not found
	return 0;
}

sub bounceSpamToModerator {
	my $self = shift;
	return $self->{spamHandlingCode} eq BOUNCE;
}

sub effectiveModerator {
	my $self = shift;
	return $self->{moderator} ? $self->{moderator} : $self->{owner};
}

sub allowLevel {
	my $self = shift;
	my $address = shift;
	my $level = 0;
	my $allowed = $self->allowed();
	
	foreach $entry (keys %{ $allowed }) {
	    print "allowLevel:allow key: $entry\n" if $main::TEST;
		if (matches( $address, $entry, $allowed->{$entry} )) {
			print "yes\n" if $main::TEST;
			if ($allowed->{$entry} == WILDCARD || $allowed->{$entry} == REGEX) {
				$level = 1 if $level < 1;
				next;
			} elsif ($allowed->{$entry} == MLMATCH) {
				$level = 2 if $level < 2;
				next;
			}
			return 3;
		} else {
			print "no\n" if $main::TEST;
		}
	}
	return $level;
}

sub denyLevel {
	my $self = shift;
	my $address = shift;
	my $level = 0;
	my $denied = $self->denied();
	
	foreach $entry (keys %{ $denied }) {
	    print "allowLevel:allow key: $entry\n" if $main::TEST;
		if (matches( $address, $entry, $denied->{$entry} )) {
			print "yes\n" if $main::TEST;
			if ($denied->{$entry} == WILDCARD || $denied->{$entry} == REGEX) {
				$level = 1 if $level < 1;
				next;
			} elsif ($denied->{$entry} == MLMATCH) {
				$level = 2 if $level < 2;
				next;
			}
			return 3;
		} else {
			print "no\n" if $main::TEST;
		}
	}
	return $level;
}

sub matches {
	my ($address, $entry, $type) = @_;
	my %seen = ();
	
	print "matches: $address:$entry:$type: " if $main::TEST;
	return 1 if lc $address eq lc $entry;
	if ($type == WILDCARD) {
		$entry = substr($entry,1);
		if (MLMail::hasNoDomain($address)) {
			my $addrwithdomain = $address.'@sfu.ca';
			return 1 if $addrwithdomain =~ /$entry$/;
		} else {
			return 1 if $address =~ /$entry$/;
		}
		return 0;
	} elsif ($type == REGEX) {
		if (MLMail::hasNoDomain($address)) {
			my $addrwithdomain = $address.'@sfu.ca';
			return 1 if eval "\$addrwithdomain =~ $entry";
		} else {
			return 1 if eval "\$address =~ $entry";
		}
		return 0;
	} elsif ($type == MLMATCH) {
		my $list = new MLCache($entry);
		return 1 if $list && $list->isMemberOfExpandedList($address,\%seen);
		return 0;
	}
	return $address eq $entry;
}

sub matchesRegexInAllowList {
	my $self = shift;
	my $address = shift;
	my $level = 0;
	my $allowed = $self->allowed();
	
	foreach $entry (keys %{ $allowed }) {
	    #print "allowLevel:allow key: $entry\n";
	    next if $allowed->{$entry} != REGEX;
	    next if !matches( $address, $entry, $allowed->{$entry} );
	    return 1;
	}
	return 0;
}

sub maximumMessageSize {
	my $self = shift;
	return $self->{maximumMessageSize};
}

sub maxsize {
	my $self = shift;
	my $size = $self->{maximumMessageSize};
	return $size unless $size;  # return null if maximum size is null
	return $self->{maxsize} if $self->{maxsize};  # return saved value if set
	if ($size =~ /^([\d,\.]+)[kK]$/) { $self->{maxsize} = 1024 * $1; }
	elsif ($size =~ /^([\d,\.]+)[mM]$/) { $self->{maxsize} = 1024 * 1024 * $1; } 
	else { $self->{maxsize} = $size; }
	return $self->{maxsize};
}

sub messageExceedsMaximumSize {
	my $self = shift;
	my $msg = shift;
	return 0 unless $self->maxsize();
	my $msglength = length $msg->as_string();
	return $msglength > $self->maxsize();
}

sub messageExceedsMaximumSizeForUser {
	my $self = shift;
	my $msg = shift;
	my $sender = shift;
	my $canonicalSender = MLMail::canonicalAddress( $sender );
	if ($canonicalSender) {
		return 0 if $self->isManager($canonicalSender);
		return 0 if ($canonicalSender eq $self->owner());
	}
	return $self->messageExceedsMaximumSize($msg);
}

sub mailSizeHandling {
	my $self = shift;
	my $sender = shift;
	my $msg = shift;
	my $code = SEND;
	if ($self->messageExceedsMaximumSizeForUser($msg,$sender)) {
		$code = $self->{bigMessageHandlingCode};
		_stdout( "bigMessageHandlingCode: $code" ) if $main::TEST;
	}
	return $code;
}

sub mailHandlingCodeForUnauthSender {
	my $self = shift;
	my $sender = shift;
	my $isMember = shift;
	my $code = '';
	if (!MLMail::isLiberalLocalAddress($sender)) {
		# non-SFU address
		$code = $isMember ? $self->{nonSFUUnauthHandlingCode} : $self->{nonSFUNonmemberHandlingCode};
		return $code if $code;
	}
	# SFU address or nonSFU attributes aren't set
	return $isMember ? $self->{unauthHandlingCode} : $self->{nonmemberHandlingCode};
}

sub deliverySuspended {
	my $self = shift;
	return $self->{deliverySuspended};
}

sub hasStaleDeliveryList {
    my $self = shift;
	my $baseDir = $self->{root}."/files/".$self->{name};
    return 0 unless -e "$baseDir/deliveryList";
    return 1 unless -e "$baseDir/members";    # if no members file, the 
                                              # deliveryList is stale by default
    return (_mTime("$baseDir/deliveryList")<_mTime("$baseDir/members")) ? 1 : 0;
}

sub _mTime {
    my $file = shift;
    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, 
        $mtime,$ctime,$blksz,$blks) = stat $file;
    return $mtime;
}

sub _refreshCache {
    my $listname = shift;
    updateMaillistFiles($listname);
}
    

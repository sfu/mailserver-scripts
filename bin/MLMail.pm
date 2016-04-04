package MLMail;
use Mail::Internet;
use Mail::Address;
use lib "/opt/mail/maillist2/bin";
use LOCK;
use MLCache;
use Aliases;
use DB_File;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( canonicalAddress hasNoDomain hasLocalDomain isLocalAddress stripDomain validateUsername equivalentAddress equivalentAddresses hasSFUDomain isLiberalLocalAddress );


#
# Get the canonical form of an address
# If it looks like a local address but is invalid or inactive, return 0
#
sub canonicalAddress {
	my $addr = shift;
	my @tokens = Mail::Address->parse($addr);
	my $addrObj = pop @tokens;
	my $address = lc $addrObj->address();
	if (hasNoDomain( $address ) || hasLocalDomain( $address )) {
		# get canonical form of sfu address
		my $userPart = stripDomain( $address );
		return $userPart if isMaillist($userPart);
		if ($userPart =~ /^owner-/) {
			my $maillist = new MLCache(substr $userPart, 6);
			return $maillist->owner();
		}
		return $userPart if isStaticAlias( $userPart );
		my $username = getUsername( $userPart );
		return 0 unless $username;
		return $username;
	} else {
		return $address;
	}
}


sub hasNoDomain {
	my $addr = shift;
	return -1 == index $addr, '@';
}

sub hasLocalDomain {
	my $addr = shift;
	#
	# Changes to LOCAL_DOMAINS should also be made in the AMInternetAddress
        # java class in the SFUAMmySql project
	#
	my @LOCAL_DOMAINS = qw( @sfu.ca @sfu.edu @mail.sfu.ca @mailserver.sfu.ca @mailhost.sfu.ca @rm-rstar.sfu.ca @rm-rstar1.sfu.ca @rm-rstar2.sfu.ca @fraser.sfu.ca @pop.sfu.ca @popserver.sfu.ca @imap.sfu.ca @imapserver.sfu.ca @smtp.sfu.ca @smtpserver.sfu.ca @zimbra.sfu.ca @cs.sfu.ca @ensc.sfu.ca @math.sfu.ca @stat.sfu.ca);
	foreach $domain (@LOCAL_DOMAINS) {
		return 1 if $addr =~ /$domain$/;
	}
	return 0;
}

sub hasSFUDomain {
	my $addr = shift;
	return 1 if $addr =~ /\@sfu\.ca$/;
	return 1 if $addr =~ /\@.*\.sfu\.ca$/;
	return 0;
}

sub isLocalAddress {
	my $addr = shift;
	my $canonical = canonicalAddress($addr);
	return hasNoDomain($canonical) || hasLocalDomain($canonical);
}

sub isLiberalLocalAddress {
	my $addr = shift;
	my $canonical = canonicalAddress($addr);
	return hasNoDomain($canonical) || hasSFUDomain($canonical);
}

sub stripDomain {
	my $addr = shift;
	my $index = index $addr, '@';
	return $addr if $index==-1;
	return substr $addr,0,$index;
}

sub getUsername {
	my $user = shift;
	my $username = aliasToUsername( $user );
	$username = $user unless $username;
	return validateUsername( $username );
}

sub validateUsername {
	my $username = shift;
 	return validUser($username);
 
 	#my ($name,$passwd,$uid,$gid,$q,$c,$gcos,$dir,$shell) = getpwnam $username;
 	#return undef if !defined($passwd);
 	#return undef unless $passwd;
 	#return $username if $passwd ne '*';
 	#return undef;
}

sub isMaillist {
	my $name = shift;
	return -e "/opt/mail/maillist2/files/$name";
}

sub equivalentAddress {
    my ($addr) = @_;
    my %EQUIVS=();
    tie(%EQUIVS,"DB_File","/opt/mail/equivs.db",O_RDONLY, 0644) or return '';
    my $equiv = $EQUIVS{"$addr\0"};
    $equiv = '' unless defined $equiv;
    chop $equiv if $equiv =~ /\0$/;
    return '' unless $equiv;
    my @users = split /:/, $equiv;
    untie %EQUIVS;
    return $users[0];
}

sub equivalentAddresses {
    my ($addr) = @_;
    my %EQUIVS=();
    tie(%EQUIVS,"DB_File","/opt/mail/equivs",O_RDONLY,0644) or return '';
    my $equiv = $EQUIVS{"$addr\0"};
    $equiv = '' unless defined $equiv;
    chop $equiv if $equiv =~ /\0$/;
    return undef unless $equiv;
    my @users = split /:/, $equiv;
    untie %EQUIVS;
    return @users;
}

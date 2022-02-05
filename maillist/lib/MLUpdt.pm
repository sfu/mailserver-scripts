package MLUpdt;
use Sys::Syslog;
use Mail::Internet;
use Mail::Address;
use Mail::Send;
use LWP::UserAgent;
use FileHandle;
use Digest::MD5;
use MIME::Base64;
use Date::Format;
use DB_File;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use LOCK;
use MLRestClient;
use MLRestMaillist;
use MLRestMember;
use MLUtils;
use ICATCredentials;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( updateMaillistFiles updateAllMaillists );
use vars qw($main::MLDIR $main::TEST);
use constant LOCK_SH => 1;
use constant LOCK_EX => 2;
use constant LOCK_NB => 4;
use constant LOCK_UN => 8;

# regex of lists to ignore. Format for more than one: "(list|list|list)"
my $EXCLUDES = "lightweight-accounts";

sub updateMaillistFiles {
    my $listname = shift;
    my $member = '';
    $SIG{TERM} = \&termHandler;
    $MLUpdt::LOCK = "${main::MLDIR}/$listname.lock";
    return 1 if lockInUse($MLUpdt::LOCK);
    unless (acquire_lock( $MLUpdt::LOCK )) {
        _stderr( "$$ error getting lock ${MLUpdt::LOCK}: $!" );
        return 0;
    }
    my $client = restClient();
    return cleanReturn("restClient() returned undef") unless defined $client;
    my $ml = $client->getMaillistByName( $listname );
    return cleanReturn("Failed to get maillist: $listname") unless defined $ml;

    if ($ml->lastChangeDateString() eq localTimestamp($listname)) {
      # The local files for the list are up-to-date, so return
      release_lock( $MLUpdt::LOCK );
      return 1;
    }

   # Ensure umask is set to allow world-readable files - SHillman May 8/2014
   my $oldumask = umask(0002);

    #
    # Timestamps didn't match, so update files for this list
    #
    
    createMLCacheFile($ml); # Create the dbm file for the maillist attributes
    
    #
    # Create the members file (unless this is handled by other "manual" process)
    #
    unless (isManualList($listname)) {
      my @members = $ml->members();
      return cleanReturn("rest client returned undef members") unless @members;
      # Maillists that have a subscription policy of "BYREQUEST" are ones that require owner approval.
      # These lists can have pending members who will show up in the memberCount, but not in the list
      # of members (anymore), so allow for up to 15 extra pending members in that situation
      if (($ml->memberCount() != scalar @members 
              && $ml->localSubscriptionPolicyCodeString() != 'BYREQUEST' 
              && $ml->externalSubscriptionPolicyCodeString() != 'BYREQUEST') 
           || $ml->memberCount() > scalar(@members) + 15 || !scalar(@members)) {
        unlink ${main::MLDIR}."/$listname/ts";
        return cleanReturn("rest client could not fetch members for $listname");
      }
      open(MEMBERS,">${main::MLDIR}/$listname/members");
      flock MEMBERS, LOCK_EX;
      foreach $member (@members) {
         next unless defined $member;
	 if ($main::VERBOSE)
	 {
	    _stdout("\nMember: ".$member->canonicalAddress());
	    _stdout("\n  copyOnSend: ". $member->copyOnSend());
	    _stdout("\n  manager: ". $member->manager());
	    _stdout("\n  deliver: ". $member->deliver());
	 }
         my $copyonsend = ($member->copyOnSend() == 1 || $member->copyOnSend() eq 'true') ? 1 : 0;
         my $manager = ($member->manager() == 1 || $member->manager() eq 'true') ? 1 : 0;
         my $deliver = ($member->deliver() == 1 || $member->deliver() eq 'true') ? 1 : 0;
         print MEMBERS lc $member->canonicalAddress()."\t".$member->type()."\t$manager\t$deliver\t$copyonsend\n";
      }
      close MEMBERS;
    }
    unlink "${main::MLDIR}/$listname/deliveryList" if -e "${main::MLDIR}/$listname/deliveryList";
    
    #
    # Create the allow file
    #
    my @allow = $ml->allowed();
    open(ALLOW,">${main::MLDIR}/$listname/allow");
    flock ALLOW, LOCK_EX;
    foreach $member (@allow) {
      print ALLOW $member->canonicalAddress()."\t".$member->type();
      print ALLOW "\t".$member->address() if defined($member->address());
      print ALLOW "\n";
    }
    close ALLOW;
    
    #
    # Create the deny file
    #
    my @deny = $ml->denied();
    open(DENY,">${main::MLDIR}/$listname/deny");
    flock DENY, LOCK_EX;
    foreach $member (@deny) {
      print DENY $member->canonicalAddress()."\t".$member->type();
      print DENY "\t".$member->address() if defined($member->address());
      print DENY "\n";
    }
    close DENY;
    
    #
    # Create the timestamp file
    #
    open(TS,">${main::MLDIR}/$listname/ts");
    flock TS, LOCK_EX;
    print TS $ml->lastChangeDateString()."\n";
    close TS;

   # Restore old umask
   umask($oldumask);
    
	release_lock( $MLUpdt::LOCK );
	return 1;
}

sub updateAllMaillists {
    my $ml = '';
    my $client = restClient();
    return cleanReturn("restClient() returned undef") unless defined $client;
    my $start = time();
    
    my $LISTS = $client->getMaillistSummary();
    return cleanReturn("getMaillistSummary() returned undef") 
                                                       unless defined $LISTS;
	foreach $ml (@$LISTS) {
		my $listname = $ml->name();
		if ($listname =~ /$EXCLUDES/)
		{
			_stdout("Skipping $listname. In $EXCLUDES");
			next;
		}
		if ($ml->lastChange() ne localTimestamp($listname)) {
			_stdout( "updateAllMaillists: Updating $listname" );
			updateMaillistFiles( $listname );
			_stdout( "updateAllMaillists: Finished updating $listname" );
		}
		# Force Rest client to get a new auth token if our session is getting old
		if (time() > $start+3000)
		{
			$MLUpdt::restClient = undef if (time() > $start+3000);
			$start = time();
		}
	}
}

#
# Utility subroutines
#

sub termHandler {
    my $signal = shift;
    if (-e $MLUpdt::LOCK) {
      release_lock( $MLUpdt::LOCK );
    }
    &closelog;
    $MLUpdt::TERM = 1;
    print "err interrupted\n";
    die "$$ interrupted!";
}

sub restClient {
    if (!defined $MLUpdt::restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName('robert');
       $MLUpdt::restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$main::TEST);
    }
    return $MLUpdt::restClient;
}

sub createMLCacheFile {
    my $ml = shift;
    
    my $listname = $ml->name();
    mkdir "${main::MLDIR}/$listname" unless -e "${main::MLDIR}/$listname";
    tie( %maillist, "DB_File","${main::MLDIR}/$listname/maillist.db", O_CREAT|O_RDWR,0664,$DB_HASH )
          || return cleanReturn("Can't create/open $listname/maillist.db: $!. Can't continue!");

    $maillist{activationDate} = $ml->activationDate();
    $maillist{allowedToSubscribeByEmail} = ($ml->allowedToSubscribeByEmail() == 1 || $ml->allowedToSubscribeByEmail() eq 'true') ? 1 : 0;
    $maillist{bigMessageHandlingCode} = $ml->bigMessageHandlingString();
    $maillist{createDate} = $ml->createDate();
    $maillist{defaultDeliver} = ($ml->defaultDeliver() == 1 || $ml->defaultDeliver() eq 'true') ? 1 : 0;
    $maillist{defer} = ($ml->defer() == 1 || $ml->defer() eq 'true') ? 1 : 0;
#    $maillist{deferReason} = $ml->deferReason();
    $maillist{deliverySuspended} = ($ml->deliverySuspended() == 1 || $ml->deliverySuspended() eq 'true') ? 1 : 0;
    $maillist{desc} = $ml->desc();
    $maillist{disableUnsubscribe} = ($ml->disableUnsubscribe() == 1 || $ml->disableUnsubscribe() eq 'true') ? 1 : 0;
    $maillist{errorsToAddress} = $ml->errorsToAddress();
    $maillist{expireDate} = $ml->expireDate();
    $maillist{externalDefaultAllowedToSend} = 
                        ($ml->externalDefaultAllowedToSend() == 1 || $ml->externalDefaultAllowedToSend() eq 'true') ? 1 : 0;
    $maillist{externalSenderPolicy} = $ml->externalSenderPolicy();
    $maillist{externalSubscriptionPolicy} = 
                                $ml->externalSubscriptionPolicy();
    $maillist{hidden} = ($ml->hidden() == 1 || $ml->hidden() eq 'true') ? 1 : 0;
    $maillist{lastChangeDate} = $ml->lastChangeDateString();
    $maillist{lastChanged} = $ml->lastChanged();
    $maillist{localDefaultAllowedToSend} = ($ml->localDefaultAllowedToSend() == 1 || $ml->localDefaultAllowedToSend() eq 'true') ? 1 : 0;
    $maillist{localSenderPolicy} = $ml->localSenderPolicy();
    $maillist{localSubscriptionPolicy} = 
                                 $ml->localSubscriptionPolicy();
    $maillist{maximumMessageSize} = $ml->maximumMessageSize();
    $maillist{maximumSpamLevel} = $ml->maximumSpamLevelString();
    $maillist{moderator} = $ml->moderator();
    $maillist{name} = $ml->name();
    $maillist{newOwner} = $ml->newOwner();
    $maillist{newsfeed} = $ml->newsfeed();
    $maillist{nonSFUNonmemberHandlingCode} = 
                                 $ml->nonSFUNonmemberHandlingCode();
    $maillist{nonSFUUnauthHandlingCode} = 
                                 $ml->nonSFUUnauthHandlingCode();
    $maillist{nonmemberHandlingCode} = 
                                 $ml->nonmemberHandlingCode();
    $maillist{owner} = $ml->owner();
    $maillist{ownerTransferType} = $ml->ownerTransferType();
    $maillist{requestHandler} = $ml->requestHandler();
    $maillist{spamHandlingCode} = 
                                 $ml->spamHandlingString();
    $maillist{status} = $ml->status();
    $maillist{type} = $ml->type();
    $maillist{unauthHandlingCode} = $ml->unauthHandlingCode();
    
    untie(%maillist);
}

sub localTimestamp {
	my $listname = shift;
	return ' ' unless -e  "${main::MLDIR}/$listname/ts";
	open(TS,"<${main::MLDIR}/$listname/ts");
	flock TS, LOCK_SH;
	my $ts = <TS>;
	close TS;
	chomp $ts;
	return $ts;
}
	
sub isManualList {
	my $listname = shift;
	return $listname eq 'all-registered-undergrads';
}

sub cleanReturn {
	my $msg = shift;
	_stderr($msg);
    if (-e $MLUpdt::LOCK) {
      release_lock( $MLUpdt::LOCK );
    }
	return 0;
}

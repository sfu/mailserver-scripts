#!/usr/local/bin/perl

use URI::Escape;
use lib '/opt/mail/maillist2/lib';
use MLRestClient;
use MLRestMaillist;
use MLRestMember;
use MLUpdt;
use lib '/opt/mail/maillist2/lib/amaint';
use ICATCredentials;

$main::VERBOSE = 1;
$main::TEST = 0;
$main::MLDIR = '/opt/mail/maillist2/files';
my $login = new ICATCredentials('maillist.json')->credentialForName('mlrest');
my $client = new MLRestClient($login->{username},$login->{password},$main::TEST);

my $ml = $client->getMaillistByName( 'all-undergrads' );
unless (defined $ml) { print "Not defined\n"; exit(0); }
print $ml->toString();
print scalar localtime;
print "\n";
my @members = $ml->members();
print scalar localtime;
print "\n";
#unless (defined @members) { print "members not defined\n"; exit(0); }
unless (@members) { print "members not defined\n"; exit(0); }
print scalar @members;
print "\n";
print $members[0]."\n";

exit(0);

my $name = "ra-email&telephonelists";
my $safe = uri_escape($name);
my $TOKEN = new ICATCredentials('amaint.json')->credentialForName('amaint')->{token};
my $url = "https://amaint.sfu.ca/cgi-bin/WebObjects/Maillist.woa/ra/maillists.json?name=$safe&sfu_token=$TOKEN";
print "url: $url\n";
my $data = &MLRestClient::_httpGet($url, 1);
print "data: $data\n";
exit(0);

updateAllMaillists();
exit(0);


my $ml = $client->getMaillistByName( 'nusc341-2013' );
print $ml->toString();
print "\n".$ml->nonSFUUnauthHandlingCode()."\n";
print "\n".$ml->nonSFUNonmemberHandlingCode()."\n";
print "\n".$ml->lastChangeDateString()."\n";
my @members = $ml->members();
foreach $member (@members) {
#   print $member->toString();
}
exit(0);
print "\n\n";
my @allowed = $ml->allowed();
foreach $member (@allowed) {
   print $member->toString();
}
print "\n\n";
my @denied = $ml->denied();
foreach $member (@denied) {
   print $member->toString();
}
    my %hash = ();
    $hash{activationDate} = $ml->activationDate();
    $hash{allowedToSubscribeByEmail} = ($ml->allowedToSubscribeByEmail() eq 'true') ? 1 : 0;
    $hash{bigMessageHandlingCode} = $ml->bigMessageHandlingCode();
foreach $key (keys %hash) {
   print "$key: " . $hash{$key};
}

print "\n\n";

createMLCacheFile($ml);

exit 0;
$client->addMember($ml, 'ebronte@sfu.ca');
my $ebronte = $client->getMemberForMaillistByAddress( $ml, 'ebronte' );
print $ebronte->toString();
print "\n\n";
sleep(10);
$client->deleteMember($ebronte);
exit 0;

my $aliases = $client->getAliasesTxt();
exit;
my $ml = $client->getMaillistByName( 'i-cat' );
my $result = $client->getSenderPermission($ml, 'kipling@sfu.ca');
print "Permission before set:\n";
print ref $result;
print "\n".$result->toString()."\n";
$result = $client->setSenderPermission($ml, 'kipling@sfu.ca', 'false');
print "Permission in result from set:\n";
print ref $result;
print "\n".$result->toString()."\n";
$result = $client->getSenderPermission($ml, 'kipling@sfu.ca');
print "Permission after refetch:\n";
print ref $result;
print "\n".$result->toString()."\n";

exit 0;
my @members = $client->getManagersForMaillist( $ml );
foreach $member (@members) {
    print "address: " . $member->address() . "\n";
}
@members = $ml->managers();
foreach $member (@members) {
    print "address: " . $member->address() . "\n";
}
exit 0;

my $ml = $client->getMaillistByName( 'ic-info' );
my $member = $client->getMemberForMaillistByAddress( $ml->id(), 'robert@sfu.ca' );
print $member->toString();
exit 0;

my $aliases = $client->getAliasesTxt();
print "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n------------------------------\n";
print $aliases;
print "\n------------------------------\n";
exit 0;

my $ml = $client->getMaillistByName( 'ic-info' );

my @addresses = ( 
                    {
                        address => 'kipling@sfu.ca', 
                        deliver => 'false'
                    },
                    {
                        address => 'rob.a.urquhart@gmail.com', 
                        deliver => 'false', 
                        allowedToSend => 'true'
                    },
                    {
                        address => 'ebronte', 
                        deliver => 'false'
                    },
                    {
                        address => 'rosey', 
                        deliver => 'false'
                    },
                    {
                        address => 'urquhart', 
                        deliver => 'false', 
                        allowedToSend => 'true'
                    },
                    {
                        address => 'robert', 
                        deliver => 'true', 
                        allowedToSend => 'true'
                    },
                    {
                        address => 'frances', 
                        deliver => 'false', 
                        allowedToSend => 'true'
                    }
                );
$ml = $client->replaceMembers($ml, \@addresses);
exit 0;
#my $ml = $client->getMaillistByName( 'ic-info' );
#print "name: " . $ml->name() . "\n";
#my $members = $ml->members();
#foreach $member (@$members) {
#    print "address: " . $member->{address} . "\n";
#}
# my $listOfMLs = $client->getMaillistsByMember( 'robert' );
# foreach $ml (@$listOfMLs) {
#     print "name: " . $ml->name() . "\n";
# }
# $listOfMLs = $client->getMaillistsByOwner( 'robert' );
# foreach $ml (@$listOfMLs) {
#     print "name: " . $ml->name() . "\n";
# }
# $listOfMLs = $client->getMaillistsByNameWildcard( 'icat-' );
# foreach $ml (@$listOfMLs) {
#     print "name: " . $ml->name() . "\n";
# }
#$listOfMLs = $client->getMaillistSummary( 'x' );
#foreach $ml (@$listOfMLs) {
#    print $ml->name() . "\t" . $ml->lastChange() . "\n";
#}
#my $ml = $client->getMaillistById( '1239' );
#print "name: " . $ml->name() . "\n";

#$ml = $client->getMaillistByName( 'test-rest-create' );
#my $result = $client->deleteMaillist( $ml->id(), $etag );
print "Creating test-rest-create\n";
my $ml = $client->createMaillist( "test-rest-create", "Test REST post to create a maillist");
print $ml ? "success\n" : "fail\n";
print "name: " . $ml->name() . "\n";
print "owner: " . $ml->owner() . "\n";
my $etag = $main::ETag;
my $result = $client->deleteMaillist( $ml->id(), $etag );
# print "Reading test-rest-create\n";
# $ml = $client->getMaillistByName( 'test-rest-create' );
# my $etag = $main::ETag;
# print "name: " . $ml->name() . "\n";
# print "owner: " . $ml->owner() . "\n";
# print "deliverySuspended: " . $ml->deliverySuspended() . "\n";
# print "etag: " . $etag . "\n";
# print "Updating test-rest-create\n";
# my %contentHash = ();
# $contentHash{desc} = 'New description';
# $contentHash{deliverySuspended} = 'true';
# 
# $client->modifyMaillist($ml, \%contentHash);
# $ml = $client->getMaillistByName( $ml->name() );
# my $etag = $main::ETag;
# print "name: " . $ml->name() . "\n";
# print "owner: " . $ml->owner() . "\n";
# print "deliverySuspended: " . $ml->deliverySuspended() . "\n";
# print "etag: " . $etag . "\n";
# print "Deleting test-rest-create\n";
# 
# my $result = $client->deleteMaillist( $ml->id(), $etag );

print "Creating courselist\n";
my @optional = ('autoRollover' => 'true', 
                'saveSnapshot' => 'true', 
                'autoDeleteSnapshot' => '2');
$ml = $client->createCourselist( "chin_181_d100_1127", @optional);
$ml = $client->getMaillistByName( $ml->name() );
$etag = $main::ETag;
print "name: " . $ml->name() . "\n";
print "autoRollover: " . $ml->autoRollover() . "\n";
print "saveSnapshot: " . $ml->saveSnapshot() . "\n";
print "autoDeleteSnapshot: " . $ml->autoDeleteSnapshot() . "\n";
$ml = $client->getCourselistById( $ml->id() );
$etag = $main::ETag;

print $ml->isCourselist() ? "It's a courselist\n" : "Not a courselist\n";
my @members = $ml->members();
foreach $member (@members) {
    print "address: " . $member->address() . "\n";
}
$newmember = $client->addMember($ml,'robert@sfu.ca');

@members = $ml->members();
foreach $member (@members) {
    print "address: " . $member->address() . "\n";
}

my %contentHash = ();
$contentHash{manager} = 'true';
$client->modifyMember($newmember, \%contentHash);
$newmember = $client->getMemberById($newmember->id());
print $newmember->toString() . "\n";
$client->deleteMember($newmember);

$ml = $client->getCourselistById( $ml->id() );
$etag = $main::ETag;
@members = $ml->members();
foreach $member (@members) {
    print "address: " . $member->address() . "\n";
}
$ml = $client->replaceMembers($ml, ["kipling@sfu.ca", "rob.a.urquhart@gmail.com"]);
print $ml->toString();
$result = $client->deleteMaillist( $ml->id(), $etag );
exit 0;

sub createMLCacheFile {
    my $ml = shift;
    
    my $listname = $ml->name();
    mkdir "${main::MLDIR}/$listname" unless -e "${main::MLDIR}/$listname";
	dbmopen(%maillist,"${main::MLDIR}/$listname/maillist",0664) or return cleanReturn( "can't open cache: $!" );

    $maillist{activationDate} = $ml->activationDate();
    $maillist{allowedToSubscribeByEmail} = ($ml->allowedToSubscribeByEmail() eq 'true') ? 1 : 0;
    $maillist{bigMessageHandlingCode} = $ml->bigMessageHandlingString();
    $maillist{createDate} = $ml->createDate();
    $maillist{defaultDeliver} = ($ml->defaultDeliver() eq 'true') ? 1 : 0;
    $maillist{defer} = ($ml->defer() eq 'true') ? 1 : 0;
    $maillist{deferReason} = $ml->deferReason();
    $maillist{deliverySuspended} = ($ml->deliverySuspended() eq 'true') ? 1 : 0;
    $maillist{desc} = $ml->desc();
    $maillist{disableUnsubscribe} = ($ml->disableUnsubscribe() eq 'true') ? 1 : 0;
    $maillist{errorsToAddress} = $ml->errorsToAddress();
    $maillist{expireDate} = $ml->expireDate();
    $maillist{externalDefaultAllowedToSend} = 
                        ($ml->externalDefaultAllowedToSend() eq 'true') ? 1 : 0;
    $maillist{externalSenderPolicy} = $ml->externalSenderPolicy();
    $maillist{externalSubscriptionPolicy} = 
                                $ml->externalSubscriptionPolicy();
    $maillist{hidden} = ($ml->hidden() eq 'true') ? 1 : 0;
    $maillist{lastChangeDate} = $ml->lastChangeDateString();
    $maillist{lastChanged} = $ml->lastChanged();
    $maillist{localDefaultAllowedToSend} = ($ml->localDefaultAllowedToSend() eq 'true') ? 1 : 0;
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
    
	dbmclose %maillist;
}

sub updateAllMaillists {
    my $list = '';
    my $client = restClient();
    return cleanReturn("Couldn't create MLRestCLient object") unless defined $client;
    my $LISTS = $client->getMaillistSummary();
    
# 	my $url = "https://my.sfu.ca/cgi-bin/WebObjects/ml2.woa/wa/getListNames?token=${main::TOKEN}";
# 	_stderr("updateAllMaillists: Getting $url");
# 	my $mldata = '';
# 	my $ua = LWP::UserAgent->new;
# 	$ua->timeout(90);
# 	my $getcounter = 0;
# GET:
# 	for (;;) {
# 	  $getcounter++;
#       # ua->get catches the die issued by the SIGTERM handler, so
#       # I have the handler set MLD::TERM, then test it after the call to get.
#       $MLUpdt::TERM = 0;
#       my $response = $ua->get($url);
#       if ($response->is_success) {
#         $main::sleepCounter = 0;
#         $mldata = $response->content;
#         last;
#       }
#       die "updateAllMaillists: interrupted getting listnames" if $MLUpdt::TERM;
#       _stderr( "get for $url not successful:". $response->code );
#       if ($getcounter == 4) {
#         _stderr( "get for $url failed 4 times. Exiting." );
#         exit(0);
#       }
#       _sleep();
#       next GET;
#    }
	#my @LISTS = split /\n/,$mldata;
	foreach $list (@$LISTS) {
		#my ($listname,$timestamp) = split /\t/, $list;
		my $listname = $list->name();
		my $timestamp = $list->lastChange();
		#print ".";
		if ($timestamp ne localTimestamp($listname)) {
		    #if ($listname eq 'ic-info') {
			   print( "\nupdateAllMaillists: Updating $listname; " );
		       print "$timestamp != ".localTimestamp($listname).".\n";
		    #}
			#updateMaillistFiles( $listname ) if $listname eq 'ic-info';
			#_stdout( "updateAllMaillists: Finished updating $listname" );
			#sleep 1;
		}
	}
}

sub restClient {
    if (!defined $MLUpdt::restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName('robert');
       $MLUpdt::restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$main::TEST);
    }
    return $MLUpdt::restClient;
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

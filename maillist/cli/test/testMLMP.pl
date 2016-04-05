#!/usr/local/bin/perl
use Getopt::Std;
use FileHandle;
use lib "/usr/local/mail/maillist2/cli";
use MLMP1Server;
use MLCLIUtils;
use MLHelp;
use MLMaillist;
use lib "/usr/local/mail/maillist2/lib";
use MLRestMaillist;
use strict;

my $MLMPSERVER = MLMP1Server->new();
$MLMPSERVER->authenticate($main::opt_s) || die "Service error:".$MLMPSERVER->error();

print "isAdminUser: ".$MLMPSERVER->isAdminUser()."\n";
print "canCreateCourselist: ".$MLMPSERVER->canCreateCourselist()."\n";

my $ml = $MLMPSERVER->getMaillistByName('ic-info');
#$ml->display();
my $addrs = $MLMPSERVER->deniedSenders('ic-info');
foreach my $addr (@$addrs) {
   print "$addr\n";
}
exit 0;

my $restClient = $MLMPSERVER->{SERVICE};
my $icinfo = $restClient->getMaillistByName('ic-info');
print 'icinfo name: '.$icinfo->name()."\n";
my $maillist = new MLMaillist($icinfo, $MLMPSERVER);
print "name: ".$maillist->name()."\n";
print "type: ".$maillist->type()."\n";
print "status: ".$maillist->status()."\n";
print "owner: ".$maillist->owner()."\n";
print "actdate: ".$maillist->actdate()."\n";
print "expdate: ".$maillist->expdate()."\n";
print "newsfeed: ".$maillist->newsfeed()."\n";
print "description: ".$maillist->description()."\n";
print "allowedToSend: ".$maillist->allowedToSend()."\n";
print "moderated: ".$maillist->moderated()."\n";
print "subscribeByEmail: ".$maillist->subscribeByEmail()."\n";
print "isCourselist: ".$maillist->isCourselist()."\n";
print "isOpen: ".$maillist->isOpen()."\n";
print "isClosed: ".$maillist->isClosed()."\n";
print "isRestricted: ".$maillist->isRestricted()."\n";
print "note: ".$maillist->note()."\n";
print "managers: ";
my $managers = $maillist->managers();
foreach my $manager (@$managers) {
   print "$manager\n";
}
print "urquhart is manager: ".$maillist->isManager('urquhart')."\n";
print "kipling is manager: ".$maillist->isManager('kipling')."\n";
print "amaint is manager: ".$maillist->isManager('amaint')."\n";

print "allowedToSend: ";
my $allowed = $maillist->allowedSenders();
foreach my $addr (@$allowed) {
   print "$addr\n";
}

print "Adding foo\@bar.com to allowed\n";
$maillist->addAllowed('foo@bar.com');
print "allowedToSend after add: ";
my $allowed = $maillist->allowedSenders();
foreach my $addr (@$allowed) {
   print "$addr\n";
}
print "Removing foo\@bar.com from allowed\n";
$maillist->deleteAllowed('foo@bar.com');
print "allowedToSend after delete: ";
$allowed = $maillist->allowedSenders();
foreach my $addr (@$allowed) {
   print "$addr\n";
}


print "deniedFromSend: ";
my $denied = $maillist->deniedSenders();
foreach my $addr (@$denied) {
   print "$addr\n";
}

print "Adding kipling to denied\n";
$maillist->addDenied('kipling');
print "deniedSenders after add: ";
my $denied = $maillist->deniedSenders();
foreach my $addr (@$denied) {
   print "$addr\n";
}
print "Removing kipling from denied\n";
$maillist->deleteDenied('kipling');
print "deniedSenders after delete: ";
$denied = $maillist->deniedSenders();
foreach my $addr (@$denied) {
   print "$addr\n";
}

$maillist->display();

print "members:\n";
my $members = $maillist->members();
foreach my $addr (@$members) {
   print "$addr\n";
}

print "Course members:\n";
my $members = $maillist->courseMembers();
foreach my $addr (@$members) {
   print "$addr\n";
}

my $result = $maillist->subscribe('ebronte@sfu.ca');
print "members after subscribe:\n";
my $members = $maillist->members();
foreach my $addr (@$members) {
   print "$addr\n";
}

my $result = $maillist->unsubscribe('ebronte@sfu.ca');
print "members after unsubscribe:\n";
my $members = $maillist->members();
foreach my $addr (@$members) {
   print "$addr\n";
}


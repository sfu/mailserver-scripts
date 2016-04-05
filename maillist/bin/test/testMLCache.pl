#!/usr/local/bin/perl
use Getopt::Std;
use lib "/opt/mail/maillist2/bin/test";
use MLCache;
use lib "/opt/mail/maillist2/bin";
use MLUtils;

my $name = shift;
$main::TEST = 1;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;

print "Checking default cache\n";
my $ml = new MLCache($name);
print $ml->deliverySuspended() ? "Delivery suspended.\n" : "Delivery active.\n";
print "maxsize: ".$ml->maxsize()."\n";
print "hasStaleDeliveryList: ".$ml->hasStaleDeliveryList()."\n";
print "DeliveryList: ".$ml->deliveryList()."\n";
exit 0;
print "Unauth non-SFU non-member:".$ml->mailHandlingCodeForUnauthSender('foo@foo.ca', 0)."\n";
print "Checking /tmp/maillist2 cache\n";
$ml = new MLCache($name, "/tmp/maillist2");
print "Unauth non-SFU non-member:".$ml->mailHandlingCodeForUnauthSender('foo@foo.ca', 0)."\n";
print "Checking /tmp/maillist2 cache set from MLROOT\n";
$main::MLROOT = "/tmp/maillist2";
$ml = new MLCache($name);
print "Unauth non-SFU non-member:".$ml->mailHandlingCodeForUnauthSender('foo@foo.ca', 0)."\n";

print "maximumMessageSize: ".$ml->maximumMessageSize()."\n";
print "Max size in bytes: ".$ml->maxsize()."\n";
print "Unauth SFU member:".$ml->mailHandlingCodeForUnauthSender('ebronte@sfu.ca', 1)."\n";
print "Unauth SFU non-member:".$ml->mailHandlingCodeForUnauthSender('ebronte@sfu.ca', 0)."\n";
print "Unauth SFU non-member foo\@cs.sfu.ca:".$ml->mailHandlingCodeForUnauthSender('foo@cs.sfu.ca', 0)."\n";
print "Unauth non-SFU member:".$ml->mailHandlingCodeForUnauthSender('foo@foo.ca', 1)."\n";
print "Unauth non-SFU non-member:".$ml->mailHandlingCodeForUnauthSender('foo@foo.ca', 0)."\n";

print "unauth sfu member allowedToSend(kipling\@sfu.ca): ".$ml->allowedToSend('kipling@sfu.ca')."\n";
print "unauth sfu non-member allowedToSend(ebronte\@sfu.ca): ".$ml->allowedToSend('ebronte@sfu.ca')."\n";
print "unauth sfu non-member allowedToSend(foo\@cs.sfu.ca): ".$ml->allowedToSend('foo@cs.sfu.ca')."\n";
print "unauth non-sfu member allowedToSend(RAUrqu\@aol.com): ".$ml->allowedToSend('RAUrqu@aol.com')."\n";
print "unauth non-sfu non-member allowedToSend(foo\@foo.ca): ".$ml->allowedToSend('foo@foo.ca')."\n";

open $main::MSG, "/opt/amaint/testbuec";
my $msg  = Mail::Internet->new( $main::MSG, MailFrom => "IGNORE" );
print "Message: ".$msg->as_string();
print "\n";
print "Message size: ". length $msg->as_string();
print "\n";
print "Exceeds maximum for foo\n" if $ml->messageExceedsMaximumSizeForUser($msg,"foo\@sfu.ca");
print "Exceeds maximum for robert\n" if $ml->messageExceedsMaximumSizeForUser($msg,"robert\@sfu.ca");
print "Exceeds maximum for kipling\n" if $ml->messageExceedsMaximumSizeForUser($msg,"kipling\@sfu.ca");
print "bigMessageMailHandling for kipling: ".$ml->mailSizeHandling("kipling",$msg)."\n";
exit 0;

sub _stdout($) {
    my ($line) = @_;

    print STDOUT scalar localtime() . " $line\n";
}

sub _stderr($) {
    my ($line) = @_;

    print STDERR scalar localtime() . " $line\n";
}


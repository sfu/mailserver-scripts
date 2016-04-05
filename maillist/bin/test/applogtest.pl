#!/usr/local/bin/perl
#
use lib '/opt/mail/maillist2/bin';
use AppLogQueue;
select(STDOUT); $| = 1;         # make unbuffered

$main::TEST=1;

my $msg = new SFULogMessage();
$msg->setEvent("event1");
$msg->setDetail("A test event");
$msg->setAppName("applogtest");
$msg->{timestamp} = &gettimestamp;
$msg->{tags} = ["ic-info","robert", "#mldelivery"];

my $APPLOGQUEUE = new AppLogQueue(undef,undef, $main::TEST);
$APPLOGQUEUE->queue( '/queue/ICAT.log', $msg );
$APPLOGQUEUE->runQueue();
exit(0);


sub gettimestamp {
	my ($seconds, $microseconds) = gettimeofday;
	my $millis = int $microseconds/1000;
	my $timestamp = POSIX::strftime("%FT%T.$millis%z",localtime($seconds));
	return substr($timestamp,0,length($timestamp)-2).':'.substr($timestamp,-2);
}

#!/usr/local/bin/perl
use POSIX;
use LogMessage;
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval );
use AppLog qw( log );

my $msg = new LogMessage();
$msg->{event} = "test";
$msg->{detail} = "testing stomp";
$msg->{appName} = "testLogMessage";
print $msg->xml;

my $APPLOG = new AppLog('icat2','2amq2go');
#$APPLOG->log('/queue/ICAT.test.log',$msg);
exit 0;

sub gettimestamp {
	my ($seconds, $microseconds) = gettimeofday;
	my $millis = int $microseconds/1000;
	my $timestamp = POSIX::strftime("%FT%T.$millis%z",localtime($seconds));
	return substr($timestamp,0,length($timestamp)-2).':'.substr($timestamp,-2);
}

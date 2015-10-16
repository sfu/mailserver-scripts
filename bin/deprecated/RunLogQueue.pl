#!/usr/local/bin/perl -w

use No::Worries::Log qw(*);
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval );
use Getopt::Std;
use Net::Stomp;
use lib "/opt/mail/maillist2/bin";
use AppLogQueue;
require 'getopts.pl';

getopts('t') or exit(0);
$main::MLROOT = "/opt/mail/maillist2";
$main::TEST = $opt_t ? $opt_t : 0;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
#$main::LOGFILE = "${main::MLROOT}/logs/runlogq.log"; 
#open STDOUT, ">>${main::LOGFILE}" or die "Can't redirect STDOUT";
#open STDERR, ">&STDOUT" or die "Can't dup STDOUT";
log_filter("debug caller=~^Net::STOMP::Client");
$Net::STOMP::Client::Debug = "connection api io";

$appLogQueue = new AppLogQueue('icat2','2amq2go', $opt_t);
print( "Running queue\n");
$appLogQueue->runQueue();

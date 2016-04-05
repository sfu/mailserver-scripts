#!/usr/local/bin/perl
#
use lib '/opt/mail/maillist2/bin';
use MLMail;
use MLCachetest;
select(STDOUT); $| = 1;         # make unbuffered

$main::TEST=1;
$main::DELIVER=0;
$main::QUEUEDIR='/tmp/mlqueue';
$listname = shift @ARGV;

$main::MLROOT = "/opt/mail/maillist2";
$main::MLDIR = "${main::MLROOT}/files";
$main::VERBOSE = 1;
$maillist = new MLCachetest($listname);

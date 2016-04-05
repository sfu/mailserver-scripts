#!/usr/local/bin/perl
#
use lib '/opt/mail/maillist2/bin/test';
use MLD;
select(STDOUT); $| = 1;         # make unbuffered

$main::TEST=1;
$main::DELIVER=0;
$main::MLROOT='/tmp/maillist2';
$main::QUEUEDIR='/tmp/maillist2/mlqueue';
$dir = shift @ARGV;

processMessage( $dir );
exit(0);

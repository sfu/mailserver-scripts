#!/usr/bin/perl
#
use lib '../../lib';
use MLD;
select(STDOUT); $| = 1;         # make unbuffered

$main::TEST=1;
$main::DELIVER=0;
$main::MLROOT='/tmp/maillist2';
$main::MLDIR='/tmp/maillist2/files';
$main::QUEUEDIR='/tmp/maillist2/mlqueue';
$dir = shift @ARGV;

processMessage( $dir );
exit(0);

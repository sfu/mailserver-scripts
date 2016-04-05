#! /usr/local/bin/perl
use FileHandle;
use Getopt::Std;
require 'getopts.pl';

getopts('th') or ( &printUsage && exit(0) );

$main::MLROOT = "/opt/mail/maillist2";
$main::TEST = $opt_t ? $opt_t : 0;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
$path="${main::MLROOT}/files/".$ARGV[0]."/maillist";
dbmopen(%DBM,$path,undef) or die("Can't open $path: $!\n");
foreach $key (keys %DBM) {
 print "$key: ${DBM{$key}}\n";
}
dbmclose %DBM;
exit 0;

sub printUsage {
   print "Usage: mldbmlist.pl <-t> list-name\n";
   print "       Dump the cached maillist info dbm file for the maillist\n";
   print "       named \"list-name\".";
   print "       -t  test.\n";
   print "\n";
   print "       mlupdate -h \n";
   print "       -h  Print this usage document.\n";
   print "\n";
}

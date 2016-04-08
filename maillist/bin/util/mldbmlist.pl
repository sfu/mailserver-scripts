#!/usr/bin/perl
use FileHandle;
use Getopt::Std;
use DB_File;
require 'getopts.pl';

getopts('th') or ( &printUsage && exit(0) );

$main::MLROOT = "/opt/mail/maillist2";
$main::TEST = $opt_t ? $opt_t : 0;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
$path="${main::MLROOT}/files/".$ARGV[0]."/maillist.db";
tie %DBM, "DB_File", "$path", O_RDONLY, 0660 or die("Can't open $path: $!\n");

foreach $key (keys %DBM) {
 print "$key: ${DBM{$key}}\n";
}
untie %DBM;
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

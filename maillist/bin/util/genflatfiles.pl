#!/usr/bin/perl -w
# for each maillist directory found,
# Converts contents of maillist.db file into a flat maillist.txt
# file. Probably not needed but left here just in case
use Getopt::Std;
use MIME::Base64;
use DB_File;
use lib '../../lib';
use MLUtils;
use MLCache;
use Paths;
require 'getopts.pl';
use vars qw($main::MLDIR $main::TOKEN $main::SERVICE $opt_h $opt_a);

select(STDOUT); $| = 1;         # make unbuffered

$main::MLROOT = $MAILLISTDIR;
$main::MLDIR = "${main::MLROOT}/files";

opendir FILESDIR, $main::MLDIR or die "Couldn't open files dir:$!";
foreach $maillist (readdir FILESDIR) {
   next unless -d "${main::MLROOT}/files/$maillist";
   next if $maillist eq '.';
   next if $maillist eq '..';
   next if $maillist eq 'special';
   next unless -e "${main::MLROOT}/files/$maillist/maillist.pag";
   print STDOUT "$maillist\n";
   open FLAT, ">${main::MLDIR}/$maillist/maillist.txt" or die "failed to open $maillist/maillist.txt";
   tie %DBM, "DB_File", "$main::MLROOT/files/$maillist/maillist.db", O_RDONLY, 0660 or die "failed to open $maillist/maillist.db file";
   foreach my $key (keys %DBM) {
      $value = encode_base64($DBM{$key},'');
      print FLAT "$key\n";
      print FLAT "$value\n";
   }
   close FLAT;
   untie %DBM;
}
exit 0;


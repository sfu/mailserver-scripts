#! /usr/local/bin/perl -w
use Getopt::Std;
use MIME::Base64;
use lib '/opt/mail/maillist2/bin';
use MLUtils;
use MLCache;
require 'getopts.pl';
use vars qw($main::MLDIR $main::TOKEN $main::SERVICE $opt_h $opt_a);

select(STDOUT); $| = 1;         # make unbuffered

$main::MLROOT = "/opt/mail/maillist2";
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
   dbmopen %DBM, "${main::MLDIR}/$maillist/maillist", undef or die "failed to open $maillist/maillist dbm file";
   foreach my $key (keys %DBM) {
      $value = encode_base64($DBM{$key},'');
      print FLAT "$key\n";
      print FLAT "$value\n";
   }
   close FLAT;
   dbmclose %DBM;
}
exit 0;


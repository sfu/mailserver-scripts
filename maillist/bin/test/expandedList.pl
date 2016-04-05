#!/usr/local/bin/perl

#
use lib '/opt/mail/maillist2/bin/test';
use MLCache;
select(STDOUT); $| = 1;         # make unbuffered

my $listname = shift @ARGV;
my %seen = ();
my $mlc = new MLCache($listname);
my @members = $mlc->expandedList(\%seen);
foreach $member (@members) {
 print "$member\n";
}



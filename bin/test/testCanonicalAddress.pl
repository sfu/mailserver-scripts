#!/usr/local/bin/perl
use Getopt::Std;
use lib '/opt/mail/maillist2/bin';
use MLMailtest;


my $sender = shift;
my $canonicalSender = MLMailtest::canonicalAddress($sender);
print "Canonical address: $canonicalSender\n";
exit 0;


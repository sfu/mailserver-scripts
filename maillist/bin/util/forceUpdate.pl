#! /usr/local/bin/perl -w

while (<>) {
  chomp;
  my $tsfile="/opt/mail/maillist2/files/$_/ts";
  unlink $tsfile;
}
system "/opt/mail/maillist2/bin/mlupdate.pl -a";

0;

#!/usr/local/bin/perl -w
undef $/;
$listname = shift @ARGV;
unless($listname) {
  print "You must supply a listname as the commandline argument\n";
  exit 1;
}
while (<>)  {
   open( MSG, "|/opt/mail/maillist2/bin/test/mlqtest.pl $listname 3.5" );
   print MSG $_;
   close MSG;
}
exit 0;


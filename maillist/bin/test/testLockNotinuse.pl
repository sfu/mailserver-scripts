#!/usr/local/bin/perl

use lib '/opt/mail/maillist2/bin/test';
use LOCK;

my $LOCK = "test.lock";
$main::TEST = 1;

print "Testing lockInUse\n";
if (lockInUse($LOCK)) {
       print( "Fail - lockInUse returned true." );
       exit(0);
} else {
   print "Testing acqire_lock\n";
   acquire_lock($LOCK);
   print "Testing release_lock\n";
   release_lock($LOCK);
}


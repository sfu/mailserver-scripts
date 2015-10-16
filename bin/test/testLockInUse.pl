#!/usr/local/bin/perl

use lib '/opt/mail/maillist2/bin/test';
use LOCK;

my $LOCK = "test.lock";
$main::TEST = 1;

if (lockInUse($main::UPDATEALL_LOCK)) {
       print( "Fail" );
} else {
   print("ok");
}


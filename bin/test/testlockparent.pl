#!/usr/local/bin/perl

use lib '/opt/mail/maillist2/bin/test';
use LOCK;

$main::TEST = 1;
while ($i++<10000) {
  system("/opt/mail/maillist2/bin/test/testlock.pl","/tmp/testlock");
  system("/opt/mail/maillist2/bin/test/testlock.pl","/tmp/testlock");
}

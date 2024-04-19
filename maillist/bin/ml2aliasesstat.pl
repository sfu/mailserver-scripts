#!/usr/bin/perl -w
#
# ml2aliases file scanner
# -------------------------
# This script checks the ml2aliases file to see if it has been changed.
# If it hasn't been changed in 4 hours it sends a warning.
#
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use MLUtils;
select(STDOUT); $| = 1;         # make unbuffered
$main::DELIVER = 1;

use constant MAXTIME => 14400; # 4 hours

my ($dev,$ino,$mode,$nl,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime, $bs, $blks) 
  		= stat("$MAILDIR/ml2aliases");
if ((time - $mtime) > MAXTIME) {
  _sendMail('amaint@sfu.ca', 'ml2aliases file warning', 
            "ml2aliases file has not changed in over 4 hours on rm-rstar1", 
            'amaint@sfu.ca' );
}
exit 0;

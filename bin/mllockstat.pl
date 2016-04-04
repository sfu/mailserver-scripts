#!/usr/bin/perl -w
#
# mlqueue lock file scanner
# -------------------------
# This script checks the message queue for locks which are older than 2 hours 
# and sends a warning if it finds one.
#
use Mail::Internet;
use Getopt::Std;
use lib '/opt/mail/maillist2/bin';
use MLUtils;
select(STDOUT); $| = 1;         # make unbuffered

use constant MAXQTIME => 7200;

$main::QUEUEDIR = "/opt/mail/maillist2/mlqueue";
$main::TEST = 0;
$main::DELIVER = 1;

$hostname = `hostname -s`;
chomp $hostname;

opendir(QUEUE, $main::QUEUEDIR) or die "Can't open mlqueue directory.\n";
my @allfiles = grep(!/^\.\.?$/, readdir(QUEUE));
closedir QUEUE;
foreach $file (@allfiles) {
  next unless $file =~ /.lock$/;  # ignore anything that's not a lock file
  my ($dev,$ino,$mode,$nl,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime, $bs, $blks) 
  		= stat("${main::QUEUEDIR}/$file");
  next unless $mtime;  # lock file may have been deleted already
  if ((time - $mtime) > MAXQTIME) {
    # lock file is older than 2 hours send warning message
    _sendMail('amaint-system-messages@sfu.ca', 'mlqueue lock warning', 
              "Message has been queued for > 2 hours on $hostname: $file", 
              'amaint@sfu.ca' );
    last;
  }
}
exit 0;

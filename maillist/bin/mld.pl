#!/usr//bin/perl
#
# Maillist Delivery process
# -------------------------
# This script reads the messages in the maillist queue (see mlq.pl) and 
# forks subtasks to handle each message. The number of subtasks is limited
# to a configurable value.
# For config info, see the config file in /opt/mail/maillist2/mld.conf.
# Send the process a HUP signal to get it to reread its config file.
# The script is started at boot time (see /etc/init.d/local).
# It can be stopped with a QUIT or TERM signal. A TERM signal will 
# cause the parent process to send TERMs to all its children (see MLD.pm). 
# Otherwise, the parent just waits for the current children to complete, then
# dies.
#
use Mail::Internet;
use POSIX ":sys_wait_h";
use POSIX "setsid";
use Getopt::Std;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use MLD;
use MLUtils;
select(STDOUT); $| = 1;         # make unbuffered
$ENV{PATH} = '/bin:/usr/bin';
use vars qw($opt_c $opt_d $opt_h $opt_n $opt_t $DELIVER);

use constant CONFIGFILE => "$MAILLISTDIR/mld.conf";
use constant QUEUE => "$MAILLISTDIR/mlqueue";
use constant LOG => "$MAILLISTDIR/logs/mld.log";

getopts('c:d:htn') or ( &printUsage && exit(0) );
if ($opt_h) {
   &printUsage;
   exit(0);
}
$main::MLROOT = $MAILLISTDIR;
$main::TEST = $opt_t ? $opt_t : 0;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
$main::MLDIR = "${main::MLROOT}/files";
$main::DELIVER = $opt_n ? 0 : 1;
$main::CONFIGFILE = $opt_c ? $opt_c : CONFIGFILE;
readConfig();
_stdout( "Flags:" );
_stdout( "TEST:${main::TEST}" );
_stdout( "DELIVER:${main::DELIVER}" );

if ($opt_d) {
   &initDaemon;
} elsif ($ARGV[0]) {
   processMessage($ARGV[0]);
   exit(0);
} else {
   print "You must either start mld in daemon mode, or supply a message\n";
   print "directory to process.\n\n";
   &printUsage;
   exit(0);
}
   
%main::CHILDREN = ();
#
# The outer loop reads all the files in the queue
# and gets the message directories which are ready for delivery.
#
for (;;) {
	my $file = "";
	my %dirs = ();
    sleep(3);
	opendir(QUEUE, $main::QUEUEDIR) or die "Can't open mlqueue directory.\n";
	my @allfiles = grep(!/^\.\.?$/, readdir(QUEUE));
	closedir QUEUE;
	foreach $file (@allfiles) {
	  next unless -d "${main::QUEUEDIR}/$file";  # ignore plain files
	  my $lock = "$file.lock";
	  next if grep { $lock eq $_ } @allfiles;    # ignore directories with lock files
	  next unless -e "${main::QUEUEDIR}/$file/id";
	  next unless -e "${main::QUEUEDIR}/$file/addrs";
	  next unless -e "${main::QUEUEDIR}/$file/msg";
	  my ($dev,$ino,$mode,$nl,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime, $bs, $blks) = stat("${main::QUEUEDIR}/$file/addrs");
	  next if (time - $mtime) < 30;  # ignore if the addrs file has been touched 
	                                 # in the last 30 seconds
	  $dirs{"$ctime:$file"} = $file;
	}
	
    #
    # The inner loop spawns a process to handle each message
    # and ensures that no more than MAXMLD processes ever run.
    #
	foreach $key (sort keys %dirs) {
	  my ($ctime,$dir) = split /:/,$key;
	  waitForOpenMldSlot();
	  spawnMldProcess($dir);
	}
}
# Should never get here
exit(0);


sub printUsage {
   print "Usage: mld2.pl -d mld <-t> <-n> <-c configfile> \n";
   print "       -d mld Start mld2 in daemon mode. There can only be one daemon\n";   
   print "           running.\n";
   print "       -t  Trace. Prints lots of debugging info.\n";
   print "       -n  Non-delivery mode - message processing is done, but the\n";
   print "           final delivery is not done. Useful for testing. \n";
   print "       -c  \"file\" is a config file to use, rather than the \n";
   print "           default config at $MAILLISTDIR/mld.conf.\n";
   print "\n";
   print "       mld2.pl <-t> <-n> <-c file> message_dir   \n";
   print "           Manually process a single message in the queue.\n";
   print "\n";
   print "       mld2.pl -h \n";
   print "       -h  Print this usage document.\n";
   print "\n";
}

sub initDaemon {
	die("Pid file ${main::PIDFILE} exists. Is mld daemon running?") if -e $main::PIDFILE;
	my $pid = '';
	# fork to dissociate from terminal
	if ($pid = fork) {
	   # parent
	   exit 0;
	} else {
	   die "Cannot fork daemon: $!" unless defined $pid;
	   # child
	}
	rename ${main::LOGFILE}, "${main::LOGFILE}.".time();
	close STDOUT;
	close STDERR;
	open STDOUT, ">>${main::LOGFILE}" or die "Can't redirect STDOUT";
	open STDERR, '>>&STDOUT' or die "Can't dup STDOUT";
	select STDERR; $| = 1;
	select STDOUT; $| = 1;
	my $sess_id = POSIX::setsid();
	open PID, ">${main::PIDFILE}" or die "Can't open ${main::PIDFILE} for writing: $!";
	print PID "$$";
	close PID;
	$SIG{HUP}  = \&hupHandler;
	$SIG{INT}  = 'IGNORE';
	$SIG{STOP}  = 'IGNORE';
	$SIG{QUIT}  = \&intHandler;;
	$SIG{TERM}  = \&intHandler;
	$SIG{CHLD} = \&REAPER;
	_stdout("mld process started");
}

sub hupHandler {
   $SIG{'HUP'}  = \&hupHandler;
   readConfig();
}

#
# Handle interrupts signals.
# If a TERM signal is received, this sends a TERM to all children.
# 
sub intHandler {
   my ($signal) = @_;
   my $child;
   _stdout( "Got $signal signal." );
   unlink $main::PIDFILE;
   _stdout( "Sending TERM signals to children" ) if $signal eq 'TERM';
   kill 'TERM', keys %main::CHILDREN if $signal eq 'TERM';
   _stdout( "Waiting for child processes" );
   while(scalar(keys %main::CHILDREN) >0) {
      &REAPER;
   }
   _stdout("mld process terminated");
   exit 0;
}

sub readConfig {
   open(CONFIG, $main::CONFIGFILE) or die "Can't open ${main::CONFIGFILE}: $!";
   _stdout( "Reading config file ${main::CONFIGFILE}" );
   while (<CONFIG>) {
      next if /^#/;
      next if /^\s+$/;
      chomp;
      my ($param,$value) = split /=/;
      if ($param eq 'maxmld') { 
         $main::MAXMLD = $value;
      } elsif ($param eq 'pidfile' && !defined( $main::PIDFILE )) { 
         $main::PIDFILE = $value; 
      } elsif ($param eq 'logfile' && !defined( $main::LOGFILE )) { 
         $main::LOGFILE = $value; 
      } elsif ($param eq 'queuedir' && !defined( $main::QUEUEDIR )) { 
         $main::QUEUEDIR = $value; 
      }
   }
   close(CONFIG);
   $main::LOGFILE = LOG unless $main::LOGFILE; 
   $main::QUEUEDIR = QUEUE unless $main::QUEUEDIR; 
   _stdout( "MAXMLD:${main::MAXMLD}" );
   _stdout( "PIDFILE:${main::PIDFILE}" );
   _stdout( "LOGFILE:${main::LOGFILE}" );
   _stdout( "QUEUEDIR:${main::QUEUEDIR}" );
}

sub waitForOpenMldSlot {
   my $waitsecs = 0;
   while(scalar(keys %main::CHILDREN) >= $main::MAXMLD) {
      _stdout( "Waiting for open mld slot" ) if $main::TEST;
      sleep(1);
      if ($waitsecs++ == 300) {
          _sendMail('webmailsfu.ca', 'mld stalled', 'mld has been waiting 5 minutes for an open mld slot.', 'amaint@sfu.ca' );
      } elsif ($waitsecs == 600) {
          _sendMail('webmailsfu.ca', 'mld stalled', 'mld has been waiting 10 minutes for an open mld slot.', 'amaint@sfu.ca' );
      }
   }
}

sub spawnMldProcess {
	my ($dir) = @_;
	my $pid = '';
	if ($pid = fork) {
	   # parent
	   $main::CHILDREN{$pid} = $pid;
	   _stdout( "Spawned $pid for $dir." ) if $main::TEST;
	} else {
	   die "Cannot fork: $!" unless defined $pid;
	   # child
	   $main::CHILDREN = ();
	   MLD::processMessage($dir);
	   exit(0);
	}
}

sub REAPER {
    my $child;
    while (($child = waitpid(-1, &WNOHANG)) > 0) {
       _stdout( "Reaping $child" ) if $main::TEST;
       delete $main::CHILDREN{$child} if defined($main::CHILDREN{$child});
    }
    $SIG{CHLD} = \&REAPER;                  # install *after* calling waitpid
}



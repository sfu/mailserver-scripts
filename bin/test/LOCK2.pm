package LOCK2;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( acquire_lock release_lock check_pid lockInUse);

use constant LOCK_SH => 1;
use constant LOCK_EX => 2;
use constant LOCK_NB => 4;
use constant LOCK_UN => 8;

#
# Get a lock file. This will block until it successfully acquires the lock,
# then return 1.
# An error value of 0 is returned if opening the lock file for writing fails.
# This will happen if the supplied lock file name is too long, or if the user
# does not have write access to the file directory, or the file directory
# does not exist, or if some system i/o error occurs.
#
sub acquire_lock {
    my ($LOCK) = @_;
    my $pid = '';
    
    _stdout("$$ trying to acquire lock $LOCK") if $main::TEST;

    # Loop until we get the lock
    
    while (1) {

      open( LOCK, ">$LOCK" ) or return 0;
      unless (flock LOCK, LOCK_EX | LOCK_NB) {
         _stdout( "$$ File $LOCK already locked; waiting...\n" );
         unless (flock LOCK, LOCK_EX ) {
            close LOCK;
            next;
         }
         _stdout( "$$ got lock $LOCK\n" );
         return 1;
      }
    }
}

sub release_lock {
    my ($LOCK) = @_;
    _stdout("$$ releasing lock $LOCK") if $main::TEST;
    $count = unlink $LOCK;
    _stderr( "Could not unlink lock file: $LOCK" ) if $count!=1;
}

sub check_pid {
    my($lockpid) = @_;
    my($pid,$junk);
    
    if ($lockpid) {
        open(PS, "/usr/bin/ps -p $lockpid|");
        while (<PS>) {
            s/^\s*//;
            ($pid,$junk) = split / /,$_,2;
            if ($pid eq $lockpid) {
                close(PS);
                return(1);
            }
        }
        close(PS);
    }
    return(0);
}

sub lockInUse {
	my $LOCK = shift;
	if (-e "$LOCK") {
		_stdout("$$ found existing lock") if $main::TEST;
		open(LOCK, "<$LOCK" ) or return 0; # It may have been deleted already!
		$pid=<LOCK>;
		close (LOCK);
		chomp $pid;
		_stdout("$$ checking to see if pid $pid is active") if $main::TEST;
		return &check_pid($pid);
    }
    return 0;
}

sub _stdout($) {
    my ($line) = @_;
    
    print STDOUT scalar localtime() . " $line\n";
}

sub _stderr($) {
    my ($line) = @_;
    
    print STDERR scalar localtime() . " $line\n";
}

package AppLogQueue;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( queue runQueue );
use Sys::Syslog;
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval );
use MIME::Base64;
use Net::Stomp;
use lib "/opt/mail/maillist2/bin";
use LOCK;
use SFULogMessage;

use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;
use constant EX_UNAVAILABLE => 69;

use constant LOCK_SH => 1;
use constant LOCK_EX => 2;
use constant LOCK_NB => 4;
use constant LOCK_UN => 8;

sub new {
	my $class = shift;
	my $login = shift;
	my $passcode = shift;
	my $isTest = shift;
	my $self = {};
	bless $self, $class;
	$self->{login} = $login;
	$self->{passcode} = $passcode;
	$self->{isProd} = !$isTest;
	$self->{queueDir} = "/tmp/mlLogQueue";
	$self->{queueDir} = "/opt/mail/maillist2/mlLogQueue" if $self->{isProd};
	_stdout("queue dir is ".$self->{queueDir});
	return $self;
}

sub queue {
	my $self = shift;
	my $destination = shift;
	my $msg = shift;
	my $QFOLDER = $self->{queueDir};
	my $dir = getMsgDirName($msg);
    openlog "AppLogQueue", "pid", "mail";
	unless (acquire_lock("$QFOLDER/$dir.lock")) {
	    $self->loginfo( "AppLogQueue error getting lock file "."$QFOLDER/$dir.lock".": $!");
	    closelog();
	    return EX_TEMPFAIL;
    }
	
    if (!-e "$QFOLDER/$dir") {
        mkdir "$QFOLDER/$dir" ;          # create a queue folder for msg
        chmod 0775, "$QFOLDER/$dir";
    
        # put the destination in 'dest' file
        open DEST, ">$QFOLDER/$dir/dest";
        print DEST $destination;
        close DEST;
        # put the msg in 'msg' file
        $self->loginfo("Detail: ".$msg->detail());
        $self->loginfo("b64 encoded detail: ".encode_base64($msg->detail()));
        open MSG, ">$QFOLDER/$dir/msg";
        print MSG $msg->xml;
        close MSG;
        $self->loginfo("Added message $dir to applog queue: ".$msg->xml);
    }
    release_lock("$QFOLDER/$dir.lock");
    closelog();
    return EX_OK;
}

sub runQueue {
	my $self = shift;
	_stdout("Starting runQueue");
	my $QFOLDER = $self->{queueDir};
	my $file = "";
	opendir(QUEUE, $QFOLDER) or die "Can't open $QFOLDER directory.\n";
	my @allfiles = grep(!/^\.\.?$/, readdir(QUEUE));
	closedir QUEUE;
	my $counter = 0;
    openlog "AppLogQueue", "pid", "mail";
	foreach $file (@allfiles) {
	  _stdout("Processing file $file");
	  last if $counter++ > 100;  # Send max 100 messages.
      sleep(1) if $counter % 10 == 0;
	  next unless -d "$QFOLDER/$file";  # ignore plain files
	  my $lock = "$file.lock";
	  next if grep { $lock eq $_ } @allfiles; # ignore dirs with lock files
	  next unless -e "$QFOLDER/$file/dest";
	  next unless -e "$QFOLDER/$file/msg";
      # Get the lock
      unless (acquire_lock("$QFOLDER/$lock")) {
	     $self->loginfo("AppLogQueue error getting lock file "."$QFOLDER/$lock".": $!");
	     &closelog;
	     return EX_TEMPFAIL;
      }
      # Get the dest queue
	  open DEST, "$QFOLDER/$file/dest" or do { 
	                                           _stdout("Couldn't open $QFOLDER/$file/dest");
	                                           release_lock( "$QFOLDER/$lock" );
	                                           &closelog;
	                                           return EX_OK;
	  } ;      
      my $dest = <DEST>;
	  # Get the message
	  open MSG, "$QFOLDER/$file/msg" or do { 
	                                           _stdout("Couldn't open $QFOLDER/$file/msg");
	                                           release_lock( "$QFOLDER/$lock" );
	                                           &closelog;
	                                           return EX_OK;
	  };
      while( <MSG> ) {
        $msg .= $_;
      }
	  # send the message
	  my $success = 1;
	  if ($self->{isProd}) {
	     $self->loginfo("Sending $file log message to $dest" );
	     $success = eval '$self->stompSend($dest, $msg)';
	  } else {
	     $self->loginfo("Send message to stomp destination $dest: $msg");
	  }
	  deleteMessageDirectory("$QFOLDER/$file") if $success;
	  $self->loginfo("Releasing lock file: $lock" );
      release_lock( "$QFOLDER/$lock" );
	}
    &closelog;
    return EX_OK;
}

sub stompSend {
	my $self = shift;
	my $queue = shift;
	my $msg = shift;
	my $stomp = eval "Net::Stomp->new({ hostname => 'msgbroker1.tier2.sfu.ca', port => '61613' });";
	if (!$stomp) {
	    $stomp = eval "Net::Stomp->new({ hostname => 'msgbroker2.tier2.sfu.ca', port => '61613' });";
    }

	if ($stomp) {
	    $stomp->connect( { login => $self->{login}, passcode => $self->{passcode} } );
	    $stomp->send( { destination => $queue, body => $msg } );
	    $stomp->disconnect;
	    return 1;
	} else {
	    $self->loginfo("Failed to get stomp object");
	    return 0;
	}
}

sub getMsgDirName {
	my $id = shift;
	my $b64id = time().encode_base64( $id, "" );
	if (250 < length $b64id) {
		return substr($b64id,-250);
	} 
	$b64id =~ tr/\//_/; # MIME b64 charset uses '/' char, which won't work for a 
	                    # directory name.
	return $b64id;
}

sub deleteMessageDirectory {
    my ($path) = @_;
    _stdout( "unlinking $path/dest" ) if $main::TEST;
    unlink "$path/dest";
    _stdout( "unlinking $path/msg" ) if $main::TEST;
    unlink "$path/msg";
    _stdout( "rmdiring $path" ) if $main::TEST;
    rmdir($path) or syslog("err","Couldn't delete message directory %s:%s", $path, $! );
}

sub _stdout($) {
    my ($line) = @_;

    print STDOUT scalar localtime() . " $line\n";
}

sub loginfo() {
	my $self = shift;
	my $logmsg = shift;
    if ($self->{isProd}) {
       	 #syslog("info", $logmsg);
       _stdout($logmsg);
    } else {
       _stdout($logmsg);
    }
}

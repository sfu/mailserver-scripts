package SFUAppLog;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( log gettimestamp);
use Net::Stomp;
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval );
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use AppLogQueue;
use ICATCredentials;


sub new {
	my $class = shift;
	my $self = {};
	my $login = shift;
	my $passcode = shift;
	my $isTest = shift;
	bless $self, $class;
	if (!$login && !$passcode)
	{
		# Note: the user 'nullmail' which is the user that runs sendmail must have read access to /usr/local/credentials/activemq.json
		my $cred = new ICATCredentials('activemq.json')->credentialForName('activemq');
		$login = $cred->{mquser};
		$passcode = $cred->{mqpass};
	}

	$self->{queue} = AppLogQueue->new( $login, $passcode, $isTest );
	return $self;
}

sub log {
    my $self = shift;
    my $dest = shift;
    my $msg = shift;
    my $APPLOGQUEUE = $self->{queue};

$msg->{timestamp} = &gettimestamp;
    $APPLOGQUEUE->queue( $dest, $msg );

    # To prevent bottlenecks in mail delivery due to possible ActiveMQ issues, message delivery
    # is now handled completely out of band by a separate process (currently mlLogQueueRunner.jar)
    #$APPLOGQUEUE->runQueue();
}

sub gettimestamp {
	my ($seconds, $microseconds) = gettimeofday;
	my $millis = int $microseconds/1000;
	my $timestamp = POSIX::strftime("%FT%T.$millis%z",localtime($seconds));
	return substr($timestamp,0,length($timestamp)-2).':'.substr($timestamp,-2);
}

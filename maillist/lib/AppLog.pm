package AppLog;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( log gettimestamp);
use Net::Stomp;
use Time::HiRes  qw( usleep ualarm gettimeofday tv_interval );

sub new {
	my $class = shift;
	my $self = {};
	my $login = shift;
	my $passcode = shift;
	my $isProd = shift;
	bless $self, $class;
	$self->{stomp} = Net::Stomp->new( { hostname => 'msgbroker.sfu.ca', port => '61613' } );
	$self->{login} = $login;
	$self->{passcode} = $passcode;
	return $self;
}

sub log {
	my $self = shift;
	my $queue = shift;
	my $msg = shift;
	my $stomp = $self->{stomp};

	$msg->{timestamp} = &gettimestamp;
	$stomp->connect( { login => $self->{login}, passcode => $self->{passcode} } );
	$stomp->send( { destination => $queue, body => $msg->xml } );
	$stomp->disconnect;
}

sub gettimestamp {
	my ($seconds, $microseconds) = gettimeofday;
	my $millis = int $microseconds/1000;
	my $timestamp = POSIX::strftime("%FT%T.$millis%z",localtime($seconds));
	return substr($timestamp,0,length($timestamp)-2).':'.substr($timestamp,-2);
}

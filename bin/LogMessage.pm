package LogMessage;

require Exporter;
@ISA    = qw(Exporter);
require XML::Generator;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	$self->{instance} = '0';
	$self->{sessionId} = '0';
	$self->{clientIp} = '';
	chomp( $self->{hostname} = `hostname` );
	$self->{user} = getpwuid($<);
	return $self;
}

sub appName {
	my $self = shift;
	return $self->{appName};
}

sub hostname {
	my $self = shift;
	return $self->{hostname};
}

sub clientIp {
	my $self = shift;
	return $self->{clientIp};
}

sub user {
	my $self = shift;
	return $self->{user};
}

sub event {
	my $self = shift;
	return $self->{event};
}

sub timestamp {
	my $self = shift;
	return $self->{timestamp};
}

sub detail {
	my $self = shift;
	return $self->{detail};
}

sub tags {
	my $self = shift;
	return $self->{tags};
}

sub xml {
	my $self = shift;
	my $X = XML::Generator->new(':pretty');
	return $X->LogMessage(
			 $X->appName( $self->{appName} ),
			 $X->instance( $self->{instance} ),
			 $X->sessionId( $self->{sessionId} ),
			 $X->hostname( $self->{hostname} ),
			 $X->user( $self->{user} ),
			 $X->clientIp( $self->{clientIp} ),
			 $X->event( $self->{event} ),
			 $X->timestamp( $self->{timestamp} ),
			 $X->detail( $self->{detail} ),
			 $X->tags( $self->{tags} )
		   );
}


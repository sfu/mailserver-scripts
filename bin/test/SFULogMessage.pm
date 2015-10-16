package SFULogMessage;

require Exporter;
@ISA    = qw(Exporter);
require XML::Generator;
use MIME::Base64;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	$self->{instance} = '0';
	$self->{sessionId} = '0';
	$self->{clientIp} = '';
	$self->{ttl} = '14';
	chomp( $self->{hostname} = `hostname` );
	$self->{user} = getpwuid($<);
	return $self;
}

sub appName {
	my $self = shift;
	return $self->{appName};
}

sub setAppName {
    my $self = shift;
    my $newvalue = shift;
    $self->{appName} = $newvalue;
}

sub hostname {
	my $self = shift;
	return $self->{hostname};
}

sub clientIp {
	my $self = shift;
	return $self->{clientIp};
}

sub setClientIp {
    my $self = shift;
    my $newvalue = shift;
    $self->{clientIp} = $newvalue;
}

sub user {
	my $self = shift;
	return $self->{user};
}

sub setUser {
    my $self = shift;
    my $newvalue = shift;
    $self->{user} = $newvalue;
}

sub event {
	my $self = shift;
	return $self->{event};
}

sub setEvent {
    my $self = shift;
    my $newvalue = shift;
    $self->{event} = $newvalue;
}

sub timestamp {
	my $self = shift;
	return $self->{timestamp};
}

sub ttl {
	my $self = shift;
	return $self->{timestamp};
}

sub setTtl {
    my $self = shift;
    my $newvalue = shift;
    $self->{ttl} = $newvalue;
}

sub detail {
	my $self = shift;
	return decode_base64($self->{detail});
}

sub setDetail {
    my $self = shift;
    my $newvalue = shift;
    my $b64text = encode_base64( $newvalue, "" );
    $self->{detail} = $b64text;
}

sub tags {
	my $self = shift;
	return $self->{tags};
}

sub setTags {
    my $self = shift;
    my $newvalue = shift;
    die 'setTags called with argument which is not an array ref' unless ref($newvalue) eq 'ARRAY';
    $self->{tags} = $newvalue;
}

sub xml {
	my $self = shift;
	my $tagsString = '';
	foreach my $tag (@{$self->tags()}) {
	   $tagsString.='$X->string(\''.$tag.'\'),';
	}
	chop $tagsString;
	#print "tagsString: $tagsString\n";
	my $X = XML::Generator->new(escape => 'unescaped', pretty => 2);
	return $X->LogMessage(
			 $X->appName( $self->{appName} ),
			 $X->instance( $self->{instance} ),
			 $X->sessionId( $self->{sessionId} ),
			 $X->hostname( $self->{hostname} ),
			 $X->user( $self->{user} ),
			 $X->clientIp( $self->{clientIp} ),
			 $X->event( $self->{event} ),
			 $X->timestamp( $self->{timestamp} ),
			 $X->ttl( $self->{ttl} ),
			 $X->detail( "BASE64_".$self->{detail} ),
			 $X->tags( eval $tagsString )
		   );
}


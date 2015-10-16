package ICATCredentials;
use Utils;
use JSON;
require Exporter;
@ISA = qw(Exporter);

sub new {
    my $class = shift;
    my $name  = shift;
    my $dir   = shift;
    my $self  = {};
    bless $self, $class;
    return $self->init( $name, $dir );
}

sub init {
    my $self = shift;
    my $name = shift;

    $self->{name}    = $name;
    $self->{credDir} = $dir;
    $self->{credDir} = "/usr/local/credentials/" unless $dir;
    my $credfile = $self->{credDir} . $name;
    print( "credfile is " . $credfile ) if $main::TEST;
    local $/;
    open( my $fh, '<', $credfile );
    $json_text = <$fh>;
    $json = JSON->new->allow_nonref;
    $self->{cred} = $json->decode($json_text);
    return $self;
}

sub credentialForName {
    my $self = shift;
    my $key  = shift;

    return $self->{cred}->{$key};
}

1
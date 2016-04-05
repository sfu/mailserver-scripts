package MLRestDenyItem;
use Carp;

require Exporter;
@ISA    = qw(Exporter);

my $LOG = \*STDOUT;

sub new {
    my $that  = shift;
    my $class = ref($that) || $that;
    my $client = shift;
    my $data  = shift;
    my $log   = shift;
    $LOG = $log if $log;
    my $self = {
        %$data,
    };
    bless $self, $class;
    $self->{client} = $client;
    $self->{etag} = $main::ETag;
    return $self;
}

#
# Method autoloading
# See Programming Perl (2nd edition) pg 298. (The blue camel book)
#
sub AUTOLOAD {
    my $self = shift;
    my $type = ref($self) || croak "$self is not an object";
    my $name = $AUTOLOAD;
    $name =~ s/.*://;     # strip fully qualified portion
    unless (exists $self->{$name} ) {
        croak "Can't access $name field in object of class $type";
    }
    if (@_) {
        return $self->{$name} = shift;
    } else {
        return $self->{$name};
    }
}

sub isMaillist {
    my $self = shift;
    
    return $self->type() eq '3';
}

sub isLocalMember {
    my $self = shift;
    
    return $self->type() eq '1';
}

sub isExternal {
    my $self = shift;
    
    return $self->type() eq '2';
}

sub toString {
    $self = shift;
    my $str = '';
    
    foreach $key (keys %$self) {
      $str .= "$key: ";
      $str .= $self->{$key};
      $str .= "\n";
    }
    $str .= "\n";
    return $str;
}
package MLRestMaillist;
use Carp;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use MLRestAllowItem;
use MLRestDenyItem;
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
    unless (defined $self->{name}) { return undef; }
    bless $self, $class;
    $self->{client} = $client;
    $self->{etag} = $main::ETag;
    $self->init();
    return $self;
}

sub init {
    my $self = shift;
    
    %SENDER_POLICIES = (
        UNRESTRICTED => 0,
        RESTRICTED   => 1
    );
    
    %SUBSCRIPTION_POLICIES = (
        OPEN      =>  1,
        BYREQUEST => 20,
        OWNERONLY => 30
    );
    
    %MAILLIST_TYPES = (
        MAILLIST         => 0,
        DYNAMICLIST      => 1,
        COURSELIST       => 2,
        ACADEMICPLANLIST => 3,
        GROUPERLIST      => 4,
    );

    if ($self->{status} eq 'defined') {
        $self->{lastChangeDateString} = ' ';
    }
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

sub allowed {
    $self = shift;
    
    my $arrayRef = $self->{allowed};
    my @allowList = ();
    foreach $item (@$arrayRef) {
        push @allowList, new MLRestAllowItem($self->{client},$item);
    }
    return @allowList;
}

sub denied {
    $self = shift;
    
    my $arrayRef = $self->{denied};
    my @denyList = ();
    foreach $item (@$arrayRef) {
        push @denyList, new MLRestDenyItem($self->{client},$item);
    }
    return @denyList;
}

sub members {
    $self = shift;
    
    return $self->{client}->getMembersForMaillist($self);
}

sub managers {
    $self = shift;
    
    return $self->{client}->getManagersForMaillist($self);
}

sub modify {
    my $self = shift;
    my $contentHash = shift;

    return $self->{client}->modifyMaillist($self, $contentHash);
}

sub isCourselist {
    $self = shift;
    
    return $self->type() eq '2';
}

sub isPlanlist {
    $self = shift;
    
    return $self->type() eq '3';
}

sub externalSenderPolicy {
    $self = shift;

    return $SENDER_POLICIES{ $self->externalSenderPolicyCodeString() };
}

sub externalSubscriptionPolicy {
    $self = shift;

    return $SUBSCRIPTION_POLICIES{ $self->externalSubscriptionPolicyCodeString() };
}

sub localSenderPolicy {
    $self = shift;

    return $SENDER_POLICIES{ $self->localSenderPolicyCodeString() };
}

sub localSubscriptionPolicy {
    $self = shift;

    return $SUBSCRIPTION_POLICIES{ $self->localSubscriptionPolicyCodeString() };
}

sub nonmemberHandlingCode {
    $self = shift;
    
    return $self->nonmemberHandlingString();
}

sub nonSFUUnauthHandlingCode {
    $self = shift;
    
    return $self->nonSFUUnauthHandlingString();
}

sub nonSFUNonmemberHandlingCode {
    $self = shift;
    
    return $self->nonSFUNonmemberHandlingString();
}

sub unauthHandlingCode {
    $self = shift;
    
    return $self->unauthHandlingString();
}

sub bigMessageHandlingCode {
    $self = shift;
    
    return $self->bigMessageHandlingString();
}


sub toString {
    $self = shift;
    my $str = '';
    
    foreach $key (keys %$self) {
      $str .= "$key: ";
      $str .= $self->{$key};
      $str .= "\n";
    }
    return $str;
}

sub DESTROY {}


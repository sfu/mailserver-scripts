package MLMP1Server;

require Exporter;
@ISA    = qw(Exporter);
#use SOAP::Lite;
use Socket;
use Sys::Hostname;
use URI::Escape;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# # This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use MLRestClient;
use MLRestMaillist;
use MLMaillist;


$TOKEN = "";
$ERR = "";
$ERRPREFIX = "ca.sfu.acs.maillist.MLServiceException: ";
$ERRPREFIX2 = "ns1:Server.userException, ca.sfu.acs.maillist.MLServiceException: ";
$LOGINCONTEXT = 0;
%TYPES = (
	"open"     => 'o',
	closed     => 'c',
	courselist => 's',
	planlist   => 'p'
);

%KEYMAP = (
    description     => desc,
    welcome         => welcomeMessage,
    email_subscribe => allowedToSubscribeByEmail
);

$ISTEST = 0;

sub new {
        my $self = {};
        bless $self;
        my $host = hostname();
        getUsername();
        return $self;
}

sub setErr {
	my ($err) = @_;
	$ERR = $err;
	$ERR = substr($err,length($ERRPREFIX)) if ($err =~ /^ca.sfu.acs.maillist.MLServiceException: /);
	$ERR = substr($err,length($ERRPREFIX2)) if ($err =~ /^ns1:Server.userException, ca.sfu.acs.maillist.MLServiceException: /);
}

sub getUsername {
	my $self = shift;
	$ERR = "";
	$main::LOGIN = getlogin || (getpwuid($<))[0] || die "Can't determine your computing id!";
}

sub authenticate {
	my $self = shift;
	my $saveToken = shift;
	$ERR = "";
	my $home = (getpwuid($<))[7];
	my $MLDIR    = "$home/.ml";
    my $CREDFILE = "$MLDIR/.cred";
    my $result;
	if (-e $CREDFILE) {
		open( CRED, $CREDFILE );
		$TOKEN = <CRED>;
		close CRED;
	}
	# Get a token if we want to save a new one or don't have one 
	if ($saveToken || !$TOKEN) {
		my $pass = &getpassfromterm;
 		$self->{SERVICE} = new MLRestClient( $main::LOGIN, $pass, $ISTEST, $saveToken );
	} else {
#	    $TOKEN = 'MLTOKEN_'.$TOKEN;
		$self->{SERVICE} = new MLRestClient( $main::LOGIN, $TOKEN, $ISTEST );
	}
	if ($self->{SERVICE}) {
		if (($TOKEN ne $self->{SERVICE}->{token}) && $saveToken) {
 	       if (!-e $MLDIR) {
 	          mkdir $MLDIR, 0700;
 	       }
 		   open( CRED, ">$CREDFILE");
 		   print CRED $self->{SERVICE}->{token};
 		   close CRED;
 	       chmod 0600, $CREDFILE;
		}
		$TOKEN = $self->{SERVICE}->{token};
		$LOGINCONTEXT = $self->{SERVICE}->{loginContext};
	} else {
		setErr( "REST service authentication failed" );
		return 0;
	}
	return 1;	
}

sub getpassfromterm {
  my $pass = "";
  system "stty -echo";
  print "Password for $main::LOGIN:";
  chop($pass=<STDIN>);
  print "\n";
  system "stty echo";
  return $pass;
}

sub canCreateCourselist() {
	my $self = shift;
	return $LOGINCONTEXT->{'canCreateCourselist'};
}

sub isAdminUser() {
	my $self = shift;
	return $LOGINCONTEXT->{'isAdmin'};
}

sub loginContext() {
	my $self = shift;
	return $LOGINCONTEXT;
}

sub logout {
	my $self = shift;
	
	$LOGINCONTEXT = ();
}

sub search() {
	my $self = shift;
	my $attr = shift;
	my $filter = shift;
	$ERR = "";
	
	my $resultRef;
	my @lists = ();
	if ($attr eq 'name') {
        my $safename = uri_escape($filter);
        $resultRef = $self->{SERVICE}->getMaillistsWithFilter("name=$safename");
	} elsif ($attr eq 'manager') {
	    $resultRef = $self->{SERVICE}->getMaillistsByManager( $filter );
	} else {
	    $resultRef = $self->{SERVICE}->getMaillistsWithFilter( "$attr=$filter" );
	}
	if ($resultRef) {
	    foreach $restMaillist ( @$resultRef ) {
	      my $list = new MLMaillist($restMaillist, $self);
	      push @lists, $list;
	    }
		return \@lists;
	} else {
		return 0;
	}
}

sub getMaillistByName {
    my $self = shift;
    my $listname = shift;
    
    my $listinfo = $self->{SERVICE}->getMaillistByName($listname);
    if ($listinfo) {
        return new MLMaillist($listinfo, $self);
    } else {
        my $code = $main::HTTPCODE;
        if ($code == 404) {
            setErr("No such list: $listname");
        } else {
            setErr("Error ($code) getting list: $listname");
        }
        return 0;
    }
}

sub get() {
	my $self = shift;
	my $listname = shift;
	my $key = shift;
	$ERR = "";
	
	my $maillist = $self->getMaillistByName($listname);
	return $maillist->get($key);
}

sub getSections() {
	my $self = shift;
	my $course = shift;
	my $semester = shift;
	$ERR = "";
	
	my $len = length $course;
	my $crsename = substr($course,0,$len-3);
	my $crsenum  = substr($course,$len-3);
	my $result = $self->{SERVICE}->sections($crsename, $crsenum, $semester);
	return $result if $result;
    my $code = $main::HTTPCODE;
    if ($code == 404) {
        setErr("No such course: $crsename $crsenum $semester");
    } elsif ($code == 406) {
        setErr("Missing course name or number");
    } else {
        setErr("Error ($code) getting sections for course: $crsename $crsenum $semester");
    }
    return 0;
}	
	
sub set() {
	my $self = shift;
	my $listname = shift;
	my $value = shift;
	my $key = shift;
	$ERR = "";
	
	my $maillist = $self->getMaillistByName($listname);
	return $maillist->set($value,$key);
}	
	
sub managers() {
	my $self = shift;
	my $listname = shift;
	$ERR = "";
	
	my $maillist = $self->getMaillistByName($listname);
	return 0 unless $maillist;
	return $maillist->managers();
}

# sub add() {
# 	my $self = shift;
# 	my $listname = shift;
# 	my $type = shift;
# 	my $address = shift;
# 	$ERR = "";
# 	
# 	unless ($address) {
# 	    setErr("No address supplied to add");
#             return 0;
#         }
# 	my $result = $SERVICE->add($TOKEN, $listname, $type, $address);
# 	unless ($result->fault) {
# 		return $result->result();
# 	} else {
# 		setErr( $result->faultstring );
# 		return 0;
# 	}
# }
	
# sub remove() {
# 	my $self = shift;
# 	my $listname = shift;
# 	my $type = shift;
# 	my $address = shift;
# 	$ERR = "";
# 	
# 	my $result = $SERVICE->remove($TOKEN, $listname, $type, $address);
# 	unless ($result->fault) {
# 		return $result->result();
# 	} else {
# 		setErr( $result->faultstring );
# 		return 0;
# 	}
# }
	
# sub members() {
# 	my $self = shift;
# 	my $listname = shift;
# 	$ERR = "";
# 	
# 	my $result = $SERVICE->members($TOKEN, $listname);
# 	unless ($result->fault) {
# 		return $result->result();
# 	} else {
# 		setErr( $result->faultstring );
# 		return 0;
# 	}
# }

# sub courselist() {
# 	my $self = shift;
# 	my $listname = shift;
# 	$ERR = "";
# 	
# 	my $result = $SERVICE->autogenMembers($TOKEN, $listname);
# 	unless ($result->fault) {
# 		return $result->result();
# 	} else {
# 		setErr( $result->faultstring );
# 		return 0;
# 	}
# }

sub checkname() {
	my $self = shift;
	my $name = shift;
	$ERR = "";
	
	my $result = $self->{SERVICE}->nameValidation($name);
	if ($main::HTTPCODE && $main::HTTPCODE != 200) {
		setErr( "Internal error: ".$main::HTTPCODE );
		return 0;
	}
		
	return $result;
}

sub create {
	my $self = shift;
	my $listname = shift;
	my $type = shift;
	my $restricted = shift;
	my $description = shift;
	my %contentHash = ();
	
	my $result = $self->{SERVICE}->createMaillist($listname, $description);
	if ($main::HTTPCODE && $main::HTTPCODE > 299) {
        if ($main::HTTPCODE == 403) {
            setErr("Authorization failure: Not authorized to create $listname");
            return 0;
        } elsif ($main::HTTPCODE == 400) {
            setErr( "Name or description not provided (or invalid)" );
            return 0;
        } elsif ($main::HTTPCODE == 409) {
            setErr( "Maillist already exists: $listname" );
            return 0;
        } else {
            setErr( "Internal error: ".$main::HTTPCODE );
            return 0;
        }
	}
	my $maillist = $self->getMaillistByName($listname);
	my %contentHash = ();
	if ($type eq 'open') {
	    $type = 'OPEN';
	} else {
	    $type = 'OWNERONLY';
	}
	$contentHash{externalSubscriptionPolicyCodeString} = $type;
	$contentHash{localSubscriptionPolicyCodeString} = $type;
	
	$maillist->{RESTMAILLIST}->modify(\%contentHash);
}

sub createCourselist {
	my $self = shift;
	my $coursename = shift;
	my $semester = shift;
	my $name = shift;
	
	$coursename .= "_$semester" if $semester;
	%optional = ();
	$optional{'name'} = $name if $name;
	my $courselist = $self->{SERVICE}->createCourselist($coursename, %optional);
	if ($main::HTTPCODE && $main::HTTPCODE > 299) {
        if ($main::HTTPCODE == 403) {
            setErr( "Authorization failure: Not authorized to create courselist" );
        } elsif ($main::HTTPCODE == 400) {
            setErr( "Rostername not provided, or invalid." );
        } elsif ($main::HTTPCODE == 409) {
            setErr( "Name conflicts with existing maillist or courselist." );
        } else {
            setErr( "Internal error: ".$main::HTTPCODE );
        }
        return 0;
	}
	return $courselist ? $courselist->name() : 0;
}

sub delete {
	my $self = shift;
	my $listname = shift;
	my $maillist = $self->{SERVICE}->getMaillistByName($listname);
    if ($main::HTTPCODE == 404) {
		setErr( "No such maillist: $listname" );
		return 0;	
	}
	my $result = $self->{SERVICE}->deleteMaillist($maillist->id(), $maillist->etag());
	if ($main::HTTPCODE && $main::HTTPCODE > 299) {
        if ($main::HTTPCODE == 403) {
            setErr( "Authorization failure: Not authorized to delete $listname" );
            return 0;
        } elsif ($main::HTTPCODE == 404) {
            setErr( "No such maillist: $listname" );
            return 0;
        } elsif ($main::HTTPCODE == 412) {
            setErr( "Precondition failed: $listname has changed" );
            return 0;
        } else {
            setErr( "Internal error: ".$main::HTTPCODE );
            return 0;
        }
	}
	return 'ok';
}

sub allowedSenders() {
	my $self = shift;
	my $listname = shift;
	$ERR = "";
	
	my $maillist = $self->getMaillistByName( $listname );
	return $maillist ? $maillist->allowedSenders() : 0;
}


sub deniedSenders() {
	my $self = shift;
	my $listname = shift;
	$ERR = "";
	
	my $maillist = $self->getMaillistByName( $listname );
	return $maillist ? $maillist->deniedSenders() : 0;
}

sub subscribe() {
	my $self = shift;
	my $listname = shift;
	my $address = shift;
	my $result = "";
	$ERR = "";
	
	$result = $self->{SERVICE}->addMember($listname, $address);
	return 1 if $result;
	
	if ($main::HTTPCODE && $main::HTTPCODE > 299) {
        if ($main::HTTPCODE == 403) {
            setErr( "Authorization failure: Not authorized to subscribe to $listname" );
        } elsif ($main::HTTPCODE == 404) {
            setErr( "No such maillist: $listname" );
        } else {
            setErr( "Internal error: ".$main::HTTPCODE );
        }
	}
	return 0;
}

sub unsubscribe() {
	my $self = shift;
	my $listname = shift;
	my $address = shift;
	my $result = "";
	$ERR = "";
	
	my $maillist = $self->getMaillistByName( $listname );
	return 0 unless $maillist;
	return $maillist->unsubscribe($address);
}

# sub updateChangedGroups() {
# 	my $self = shift;
# 	my $result = "";
# 	$ERR = "";
# 	
# 	$result = $SERVICE->updateChangedGroups($TOKEN);
# 	if ($result->fault) {
# 	   setErr( join ', ', $result->faultcode, $result->faultstring );
# 	   return 0;
# 	}
# 
# 	return 1 if $result->result() =~ /^ok/;
# 	setErr( $result->result() );
# 	return 0;
# }

sub error {
	my $self = shift;
	
	return $ERR;
}

sub echo {
        my $self = shift;

        my $result = $SERVICE->echo(shift);
	if ($result->fault) {
	   setErr( join ', ', $result->faultcode, $result->faultstring );
	   return 0;
	}
	return $result->result();
}


# private methods


1;

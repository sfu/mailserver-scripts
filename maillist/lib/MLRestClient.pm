package MLRestClient;
use JSON;
use URI::Escape;
use Sys::Syslog;
use Mail::Internet;
use Mail::Address;
use Mail::Send;
use LWP::UserAgent;
use HTTP::Request::Common;
use FileHandle;
use Digest::MD5;
use MIME::Base64;
use Date::Format;
# Find the lib directory above the location of myself. Should be the same directory I'm in
# This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/../lib";
use MLRestMaillist;
use MLRestMember;
use MLRestSenderPermission;
use MLUtils;
use LOCK;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( getMaillistByName getMembers );
use vars qw($main::TEST);

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
    $self->{baseUrl} = "https://stage.its.sfu.ca/cgi-bin/WebObjects/Maillist.woa/ra/";

	$self->{baseUrl} = "https://amaint.sfu.ca/cgi-bin/WebObjects/MLRest.woa/ra/" if $self->{isProd};
	_stdout("baseUrl is ".$self->{baseUrl}) if $main::VERBOSE;
	$self->login();
	unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
	return $self;
}

sub login {
    my $self = shift;
    my $url = $self->{baseUrl} . "authenticationtoken/" . $self->{login} . ".json?password=" . $self->{passcode} . "&perm=false";
    my $mldata = _httpGet($url);
    $self->{token} = $mldata->{token};
    $self->{loginContext} = $mldata;
	_stdout("token is ".$self->{token}) if $main::VERBOSE;
}

sub _httpGet {
    my $url = shift;
    my $txt = shift;
    my $timeout = shift;
    my $ua = LWP::UserAgent->new;
	$ua->timeout($timeout ? $timeout : 30);
    $url =~ s/^http:/https:/;
	my $response;
	my $mldata = '';
	my $getcounter = 0;
GET:
	for (;;) {
	  $getcounter++;
      # ua->get catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to get.
      $MLUpdt::TERM = 0;
      my $response = $ua->get($url);
      if ($response->is_success) {
        $main::sleepCounter = 0;
        $mldata = $response->content;
        print $response->as_string() if $main::TEST; 
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return undef;
      }
      die "updateAllMaillists: interrupted getting listnames" if $MLUpdt::TERM;
      _stderr( "get for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "get for $url failed 4 times. Exiting." );
        exit(0);
      }
      _sleep();
      next GET;
   }
   print STDOUT "$mldata\n" if $main::VERBOSE;
   return $mldata if $txt;
   $json = JSON->new->allow_nonref;
   return $json->decode( $mldata );
}

sub _httpPost {
    my $url = shift;
    my $formParams = shift;
    $url =~ s/^http:/https:/;
    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $mldata = '';
	my $getcounter = 0;
POST:
	for (;;) {
	  $getcounter++;
      # ua->post catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to post.
      $MLUpdt::TERM = 0;
      my $response = $ua->post($url, $formParams);
      if ($response->is_success) {
        $main::sleepCounter = 0;
        $mldata = $response->content;
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return undef;
      }
      die "_httpPost: interrupted by SIGTERM" if $MLUpdt::TERM;
      _stderr( "post for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "Post for $url failed 4 times. Exiting." );
        exit(0);
      }
      _sleep();
      next POST;
   }
   print STDOUT "$mldata\n" if $main::VERBOSE;
   return undef unless $mldata;
   $json = JSON->new->allow_nonref;
   return $json->decode( $mldata );
}

sub _httpPut {
    require HTTP::Request::Common;
    my $url = shift;
    my $etag = shift;
    my $contentHash = shift;
    my $timeout = shift;
	$ua->timeout($timeout ? $timeout : 30);
    $url =~ s/^http:/https:/;
    
    $json = JSON->new->allow_nonref;
    my $content = $json->encode( $contentHash );
    print "PUT content: $content\n" if $main::VERBOSE;

    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $mldata = '';
	my $getcounter = 0;
PUT:
	for (;;) {
	  $getcounter++;
      # ua->put catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to put.
      $MLUpdt::TERM = 0;
      #my $response = $ua->put($url,'If-Match' => $etag, Content => $formParams);
      my $response = $ua->request(PUT $url, 'If-Match' => $etag, 
                                            'Content' => $content ); 
      
#       my @parameters = ($url);
#       push @parameters, 'If-Match' => $etag;
#       push @parameters, 'Content' => $formParams;
#       my @suff = $ua->_process_colonic_headers(\@parameters, (ref($parameters[1]) ? 2 : 1));
#       print STDOUT "Invoking PUT\n";
#       $response = $ua->request( HTTP::Request::Common::PUT( @parameters ), @suff );

      if ($response->is_success) {
        $main::sleepCounter = 0;
        $mldata = $response->content;
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return undef;
      }
      die "_httpPut: interrupted by SIGTERM" if $MLUpdt::TERM;
      _stderr( "PUT for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "PUT for $url failed 4 times. Exiting." );
        exit(0);
      }
      _sleep();
      next PUT;
   }
   print STDOUT "$mldata\n" if $main::VERBOSE;
   $json = JSON->new->allow_nonref;
   return $json->decode( $mldata );
}

sub _httpDelete {
    my $url = shift;
    my $etag = shift;
    $url =~ s/^http:/https:/;   
    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $mldata = '';
	my $getcounter = 0;
DEL:
	for (;;) {
	  $getcounter++;
      # ua->request catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to 
      # request.
      $MLUpdt::TERM = 0;
      
      my @parameters = ($url);
      push @parameters, 'If-Match' => $etag if $etag;
      my @suff = $ua->_process_colonic_headers(\@parameters,1); 
      my $response = $ua->request( HTTP::Request::Common::DELETE( @parameters ), @suff );

      if ($response->is_success) {
        $main::sleepCounter = 0;
        $mldata = $response->content;
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return undef;
      }
      die "_httpDelete: interrupted by SIGTERM" if $MLUpdt::TERM;
      _stderr( "delete for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "Delete for $url failed 4 times. Exiting." );
        exit(0);
      }
      _sleep();
      next DEL;
   }
   print STDOUT "$mldata\n" if $main::VERBOSE;
   return $mldata;
}

sub getMaillistById {
	my $self = shift;
    my $num = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $url = $self->{baseUrl} . "maillists/$num.json?sfu_token=" . $self->{token};
	_stderr("getMaillist: Getting $url") if $main::TEST;
	my $mldata = _httpGet($url);
    return new MLRestMaillist($self, $mldata);
}
    
sub getMaillistsByManager {
	my $self = shift;
    my $name = shift;
    my $includeOwned = shift;
    
    my $filter = "manager=$name";
    $filter .= "&includeOwned=true" if $includeOwned;
    return $self->getMaillistsWithFilter($filter);
}

sub getMaillistsByMember {
	my $self = shift;
    my $name = shift;
    
    return $self->getMaillistsWithFilter("member=$name");
}

sub getMaillistByName {
	my $self = shift;
    my $name = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $safename = uri_escape($name);

    my $url = $self->{baseUrl} . "maillists.json?name=$safename&sfu_token=" . $self->{token};
	_stderr("getMaillist: Getting $url") if $main::TEST;
	my $mldata = _httpGet($url);
    return new MLRestMaillist($self, $mldata);
}

sub getMaillistsByNameWildcard {
	my $self = shift;
    my $name = shift;
    
    $name .= '*' unless $name =~ /\*/; # Append a * unless name already has one
    my $safename = uri_escape($name);
    return $self->getMaillistsWithFilter("name=$safename");
}

sub getMaillistsByOwner {
	my $self = shift;
    my $name = shift;
    
    return $self->getMaillistsWithFilter("owner=$name");
}

sub getMaillistsWithFilter {
	my $self = shift;
    my $filter = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my @results = ();
    my $url = $self->{baseUrl} . "maillists.json?$filter&sfu_token=" . $self->{token};
	my $mldata = _httpGet($url,0,90);
	print "mldata: $mldata\n" if $main::TEST;
	if (ref($mldata) eq "HASH") {
	    push @results, new MLRestMaillist($self, $mldata);
	} elsif (ref($mldata) eq "ARRAY") {
	    foreach $mlinfo (@$mldata) {
	        push @results, new MLRestMaillist($self, $mlinfo);
	    }
	}
	return \@results;
}

sub getMaillistSummary {
	my $self = shift;
    my $limit = shift;
    
    my $filter = "summary=true";
    $filter .= "&limit=$limit" if $limit;
    return $self->getMaillistsWithFilter($filter);
}

sub getMembersForMaillist {
	my $self = shift;
    my $list = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $membersUri = $list->membersUri() . "?sfu_token=" . $self->{token};
    my $memdata = _httpGet($membersUri, 0, 450);
    return undef unless $memdata;
    my @members = ();
    foreach $member (@$memdata) {
        push @members, new MLRestMember($self,$member);
    }
    return @members;
}

sub getManagersForMaillist {
	my $self = shift;
    my $list = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $managersUri = $list->managersUri() . "?sfu_token=" . $self->{token};
    my $memdata = _httpGet($managersUri);
    return undef unless $memdata;
    my @members = ();
    foreach $member (@$memdata) {
        push @members, new MLRestMember($self,$member);
    }
    return @members;
}

sub createMaillist {
	my $self = shift;
    my $name = shift;
    my $desc = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $url = $self->{baseUrl} . "maillists.json?sfu_token=" . $self->{token};
	my $mldata = _httpPost($url, [ name => $name,
	                               desc => $desc ] );
	return $mldata ? new MLRestMaillist($self, $mldata) : $mldata;
}

#
# $contentHash is a ref to a hash of keyValue pairs
#
sub modifyMaillist {
	my $self = shift;
    my $ml = shift;
    my $contentHash = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $url = $self->{baseUrl} . "maillists/" . $ml->id() . ".json?sfu_token=" . $self->{token};
    my $mldata = _httpPut($url, $ml->etag(), $contentHash);
    return $mldata;
}

sub deleteMaillist {
	my $self = shift;
    my $id = shift;
    my $etag = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $url = $self->{baseUrl} . "maillists/$id.json?sfu_token=" . $self->{token};
    my $mldata = _httpDelete( $url, $etag );
    return $mldata;
}

sub createCourselist {
	my $self = shift;
    my $rosterName = shift;
    my @optional = @_;
    
    return 0 unless $rosterName;
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $url = $self->{baseUrl} . "courselists.json?sfu_token=" . $self->{token};
    my @params = ('rosternameString' => $rosterName);
    push @params, @optional;
    
	my $mldata = _httpPost($url, \@params );
	return $mldata ? new MLRestMaillist($self, $mldata) : $mldata;
}

sub getCourselistByName {
	my $self = shift;
    my $name = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $url = $self->{baseUrl} . "courselists.json?name=$name&sfu_token=" . $self->{token};
	my $mldata = _httpGet($url);
    return new MLRestMaillist($self, $mldata);
}

sub getCourselistById {
    my $self = shift;
    return $self->getMaillistById(shift);
}

sub addMember {
    my $self = shift;
    my $ml = shift;
    my $address = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $membersUri = $ml->membersUri() . "?sfu_token=" . $self->{token};
    _stdout("membersUri is ".$membersUri) if $main::VERBOSE;
    my $memdata = _httpPost($membersUri,['address' => $address]);
	return $memdata ? new MLRestMember($self, $memdata) : $memdata;
}

sub getMemberById {
    my $self = shift;
    my $num = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $url = $self->{baseUrl} . "members/$num.json?sfu_token=" . $self->{token};
	my $memdata = _httpGet($url);
	return $memdata ? new MLRestMember($self, $memdata) : $memdata;
}

sub getMemberForMaillistByAddress {
    my $self = shift;
    my $ml = shift;
    my $address = shift;
    
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $ml_id = $ml->id();
    my $url = $self->{baseUrl} . "maillists/$ml_id/members.json?member=$address&sfu_token=" . $self->{token};
    my $memdata = _httpGet($url);
    return $memdata ? new MLRestMember($self, $memdata) : $memdata;
}

sub deleteMember {
    my $self = shift;
    my $member = shift;
    
    return _httpDelete($member->uri() . "?sfu_token=" . $self->{token});
}


#
# $contentHash is a ref to a hash of keyValue pairs
#
sub modifyMember {
	my $self = shift;
    my $member = shift;
    my $contentHash = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    
    my $url = $member->uri() . "?sfu_token=" . $self->{token};
    my $memdata = _httpPut($url, $member->etag(), $contentHash);
	return $memdata ? new MLRestMember($self, $memdata) : $memdata;
}

#
# $memberList is a ref to a list of hashes.
# Each hash MUST have an "address" key and value.
# Other valid keys are "deliver", "manager", and "allowedToSend".
#
sub replaceMembers {
	my $self = shift;
    my $ml = shift;
    my $members = shift;
    
    $memberList = _getListOfHashes($members);
    if ($main::VERBOSE) {
        foreach $member (@$memberList) {
            print "member: " . $member->{address};
        }
    }
    my $url = $ml->membersUri() . "?sfu_token=" . $self->{token};
    my %contentHash = ();
    $contentHash{'addresses'} = $memberList;
    my $mldata = _httpPut($url, $ml->etag(), \%contentHash, 120);
	return $mldata ? new MLRestMaillist($self, $mldata) : $mldata;    
}

sub getAliases {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $url = $self->{baseUrl} . "aliases?sfu_token=" . $self->{token};
	return _httpGet($url);
}

sub getAliasesTxt {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $url = $self->{baseUrl} . "aliases.txt?sfu_token=" . $self->{token};
	return _httpGet($url, 1);
}

sub getSenderPermission {
	my $self = shift;
	my $ml = shift;
	my $address = shift;
	my $recursive = shift;
	
    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }
    my $ml_id = $ml->id();
    my $recurse = $recursive ? 'true' : 'false';
    my $url = $self->{baseUrl} . "maillists/$ml_id/senderpermission.json?address=$address&recursive=$recurse&sfu_token=" . $self->{token};
	my $data = _httpGet($url);
	if (ref $data eq HASH) {
	    return new MLRestSenderPermission($self, $data);
	} elsif (ref $data eq ARRAY) {
	    my @list = ();
	    for $hash (@$data) {
	        push @list, new MLRestSenderPermission($self, $hash);
	    }
	    return \@list;
	}
	return $data;
}

sub setSenderPermission {
	my $self = shift;
	my $ml = shift;
	my $address = shift;
	my $canSend = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }

    my $ml_id = $ml->id();
    my $url = $self->{baseUrl} . "maillists/$ml_id/senderpermission.json?address=$address&sfu_token=" . $self->{token};
    my %contentHash = ();
    $contentHash{'isAllowedToSend'} = $canSend;
    my $mldata = _httpPut($url, $ml->etag(), \%contentHash);
	return $mldata ? new MLRestSenderPermission($self, $mldata) : $mldata;    
}

sub nameValidation {
	my $self = shift;
	my $newname = shift;
	
	unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }

    my $url = $self->{baseUrl} . "namevalidation/$newname.json";
	my $data = _httpGet($url);
	if (ref $data eq ARRAY) {
	    my @list = ();
	    for $str (@$data) {
	        push @list, $str;
	    }
	    return \@list;
	}
	return $data;
}

sub sections {
	my $self = shift;
	my $crsename = shift;
	my $crsenum = shift;
	my $semester = shift;

	unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }

    my $url = $self->{baseUrl} . "sections.json?crsename=$crsename&crsenum=$crsenum&sfu_token=".$self->{token};
    if ($semester) {
        $url .= "&semester=$semester";
    }
    print("url: $url\n");
	my $data = _httpGet($url);
	if (ref $data eq ARRAY) {
	    my @list = ();
	    for $str (@$data) {
	        push @list, $str;
	    }
	    return \@list;
	}
	return $data;
}

sub canonicalAddress {
	my $self = shift;
	my $address = shift;
	
	unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return undef;
    }

    my $url = $self->{baseUrl} . "canonicaladdress/$address.json";
	my $data = _httpGet($url);
	if (ref $data eq ARRAY) {
	    my @list = @$data;
	    return $list[0];
	}
	return $data;
}


sub _getListOfHashes {
    my $members = shift;
    my @listOfHashes = ();
    print "ref(members): " . ref($members) . "\n\n" if $main::VERBOSE;
    if (ref($members) eq "ARRAY") {
        return $members if scalar(@$members)==0;
        my @memberArray = @$members;
        my $item = $memberArray[0];
        print "ref(item): " . ref($item) . "\n\n" if $main::VERBOSE;
        if (ref($item) eq "HASH") {return $members;}
        elsif (not ref $item) {
            # Assume it's an address
            foreach $address (@$members) {
                print "Adding $address to list\n" if $main::VERBOSE;
                push @listOfHashes, _newHashRef($address);
            }
            return \@listOfHashes;
        }
    }
}

sub _newHashRef {
    my $address = shift;
    
    my %hash = ();
    $hash{'address'} = $address;
    return \%hash;
}

sub DESTROY {}


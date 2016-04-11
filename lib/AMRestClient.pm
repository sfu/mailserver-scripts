package AMRestClient;
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
use lib '/opt/amaint/prod/lib';
use LOCK;
use Utils;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( getMaillistByName getMembers );
use vars qw($main::TEST);

sub new {
	my $class = shift;
	my $token = shift;
	my $isTest = shift;
	my $self = {};
	bless $self, $class;
	$self->{token} = $token;
	$self->{isProd} = !$isTest;
	$self->{baseUrl} = "http://icat-rob-mp.its.sfu.ca/cgi-bin/WebObjects/Amaint.woa/-60666/ra/";

	$self->{baseUrl} = "https://amaint.sfu.ca/cgi-bin/WebObjects/AmaintRest.woa/ra/" if $self->{isProd};
	_stdout("baseUrl is ".$self->{baseUrl}) if $main::VERBOSE;
	unless ($self->{token}) {
        _stderr("No token supplied");
        return undef;
    }
	return $self;
}

# sub login {
#     my $self = shift;
#     my $url = $self->{baseUrl} . "authenticationtoken/" . $self->{login} . ".json?password=" . $self->{passcode} . "&perm=false";
#     my $mldata = _httpGet($url);
#     $self->{token} = $mldata->{token};
#     $self->{loginContext} = $mldata;
# 	_stdout("token is ".$self->{token}) if $main::VERBOSE;
# }

sub _httpGet {
    my $url = shift;
    my $etag = shift;
    my $txt = shift;
    my $timeout = shift;
    my $ua = LWP::UserAgent->new;
	$ua->timeout($timeout ? $timeout : 30);
	my $response;
	my $content = '';
	my $getcounter = 0;
GET:
	for (;;) {
	  $getcounter++;
	  my $response = "";
      # ua->get catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to get.
      $MLUpdt::TERM = 0;
      if ($etag) {
          $response = $ua->request(GET $url, 'If-None-Match' => $etag ); 
      } else {
          $response = $ua->get($url);
      }
      if ($response->is_success) {
        $main::sleepCounter = 0;
        $content = $response->content;
        print $response->as_string() if $main::TEST; 
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        $main::ETag = $response->header('ETag');
        return 0;
      }
      die "AMRestClient: interrupted" if $MLUpdt::TERM;
      _stderr( "get for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "get for $url failed 4 times. Exiting." );
        exit(0);
      }
      _sleep();
      next GET;
   }
   return $content if $txt;
   $json = JSON->new->allow_nonref;
   return $json->decode( $content );
}

sub _httpPost {
    my $url = shift;
    my $formParams = shift;
    
    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $content = '';
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
        $content = $response->content;
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return 0;
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
   return undef unless $content;
   $json = JSON->new->allow_nonref;
   return $json->decode( $content );
}

sub _httpPut {
    require HTTP::Request::Common;
    my $url = shift;
    my $etag = shift;
    my $contentHash = shift;
    
    $json = JSON->new->allow_nonref;
    my $content = $json->encode( $contentHash );
    print "PUT content: $content\n";

    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $content = '';
	my $getcounter = 0;
PUT:
	for (;;) {
	  $getcounter++;
      # ua->put catches the die issued by the SIGTERM handler, so
      # I have the handler set MLD::TERM, then test it after the call to put.
      $MLUpdt::TERM = 0;
      #my $response = $ua->put($url,'If-Match' => $etag, Content => $formParams);
       print STDOUT "Invoking PUT\n";
      my $response = $ua->request(PUT $url, 'If-Match' => $etag, 
                                            'Content' => $content ); 
      
#       my @parameters = ($url);
#       push @parameters, 'If-Match' => $etag;
#       push @parameters, 'Content' => $formParams;
#       my @suff = $ua->_process_colonic_headers(\@parameters, (ref($parameters[1]) ? 2 : 1));
#       print STDOUT "Invoking PUT\n";
#       $response = $ua->request( HTTP::Request::Common::PUT( @parameters ), @suff );
      print STDOUT "Back from PUT\n";

      if ($response->is_success) {
        $main::sleepCounter = 0;
        $content = $response->content;
        $main::ETag = $response->header('ETag');
        last;
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
   $json = JSON->new->allow_nonref;
   return $json->decode( $content );
}

sub _httpDelete {
    my $url = shift;
    my $etag = shift;
    
    my $ua = LWP::UserAgent->new;
	$ua->timeout(5);
	my $response;
	my $content = '';
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
        $content = $response->content;
        last;
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
   #print STDOUT "$content\n";
   return $content;
}

sub getNisGroups {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("Not logged in to REST service");
        return '';
    }
    
    my $url = $self->{baseUrl} . "nisgroup?sfu_token=" . $self->{token};
	_stderr("getNisGroups: Getting $url") if $main::TEST;
	my $oldEtag = $self->getNisGroupEtag();
	print "$oldEtag\n" if $main::TEST;
	my $httpGetResult = _httpGet($url, $oldEtag);
	print "etag from server: ".$main::ETag."\n" if $main::TEST;
	return undef if $main::ETag eq $oldEtag;
	 $self->updateNisGroupEtag($main::ETag);
	return $httpGetResult;
}

sub getNisGroupEtag {
	my $self = shift;
    my $etag;
    
    return "x" unless -e "/tmp/nis_group_etag";
    open( ETAG, "/tmp/nis_group_etag" ) || die "Couldn't open /tmp/nis_group_etag.\n";
    chomp( $etag = <ETAG> );
    return $etag;
}

sub updateNisGroupEtag {
	my $self = shift;
    my $etag = shift;
    open( ETAG, ">/tmp/nis_group_etag" ) || die "Couldn't open /tmp/nis_group_etag.\n";
    print ETAG "$etag\n";
    close ETAG;
}

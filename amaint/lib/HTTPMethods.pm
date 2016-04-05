package HTTPMethods;
use LWP;
use JSON;
use lib '/opt/amaint/prod/lib';
use Utils;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( _httpGet );

sub _httpGet {
    my $url = shift;
    my $txt = shift;
    my $ua = LWP::UserAgent->new;
	$ua->timeout(30);
	my $response;
	my $data = '';
	my $getcounter = 0;
GET:
	for (;;) {
	  $getcounter++;
      # ua->get catches the die issued by the SIGTERM handler, so I
      # have the handler set Amaintr::TERM, then test it after the call to get.
      $Amaintr::TERM = 0;
      my $response = $ua->get($url);
      if ($response->is_success) {
        $main::sleepCounter = 0;
        $data = $response->content;
        print $response->as_string() if $main::TEST; 
        $main::ETag = $response->header('ETag');
        last;
      } else {
        $main::HTTPCODE = $response->code();
        return "err http code: " . $response->code();
      }
      die "_httpGet: interrupted" if $Amaintr::TERM;
      _stderr( "get for $url not successful:". $response->code );
      if ($getcounter == 4) {
        _stderr( "get for $url failed 4 times." );
        return "err get for $url failed 4 times";
      }
      _sleep();
      next GET;
   }
   return $data if $txt;
   $json = JSON->new->allow_nonref;
   return $json->decode( $data );
}

1;

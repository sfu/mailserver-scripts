#!/usr/bin/perl
#
# Compare a maillist's delivery list as stored on the current mail server
# with what's in the Maillist app database. Pass in list name as first argument
#
use LWP::UserAgent;
use URI::Escape;
use lib '../../lib';
use MLD;
use MLMail;
use MLCache;
select(STDOUT); $| = 1;         # make unbuffered

use constant BASEURL  => "https://my.sfu.ca/cgi-bin/WebObjects/ml2.woa/wa/";


	$listname = shift @ARGV;
        unlink "/opt/mail/maillist2/files/$listname/deliveryList";
	$maillist = new MLCache($listname);
	$locallist = $maillist->deliveryList();
	my $escapedListname = uri_escape($listname);
	$urllist = getFromMaillist("deliveryList", "maillist=$escapedListname&sender=postmast");
	if (compare($locallist, $urllist)) {
	   print "match!\n";
	} else {
           print "$listname\n";
	   print "OLD *******************************\n";
	   print "$urllist\n";
	   print "NEW *******************************\n";
           print "$locallist\n";
	}
exit 0;

sub getFromMaillist {
   my ($cmd,$argstring) = @_;
   my $content = "";
   my $i=0;
   my $pattern = "^ok $cmd";
   my $url = BASEURL . $cmd . "?" . $argstring;
GET:
   for ($i=0;$i<2;$i++) {
      $content = getFromURL($url);      
      if ($content =~ /$pattern/i) {
         my $start = length("ok $cmd") +1;
         return substr($content, $start);
      }
      print( "getFromURL for $url returned $content"  );
      sleep 30;
      next GET;
   }
}

sub getFromURL {
   my ($url) = @_;
   my $i = 0;
   my $ua = LWP::UserAgent->new;
   $ua->timeout(90);
GET:
   for (;;) {
     my $response = $ua->get($url);
     if ($response->is_success) {
       $main::sleepCounter = 0;
       return $response->content;
     }
     print( "get for $url not successful:". $response->code );
	 sleep 10;
	 next GET;
   }
}


sub compare {
	my ($local,$remote) = @_;
	my $i = 0;
	my %hash = ();
	chomp $local;
	chomp $remote;
	my @local = sort split /\n/, $local;
	my @remote = sort split /\n/, $remote;
	foreach $key (@remote) {
           $key =~ tr/>//d;
           $key =~ tr/<//d;
	   $hash{lc $key} = 1;
	}
	@remote = sort keys %hash;
	return 0 if $#local != $#remote;
	for ($i=0; $i<=$#local; $i++) {
		if ($local[$i] ne $remote[$i]) {
			print "Not equal at new:".$local[$i]." old:".$remote[$i]."\n";
			return 0;
		}
	}
	return 1;
}


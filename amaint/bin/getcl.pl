#! /usr/local/bin/perl
#
# getcl.pl : A program to extract classlist info 
#	    from Sybase and use it to generate a report of class sizes for
#           the bookstore.
#
# Changes
# -------
#   Updated for Single-ID changes.                        2007/03/27  RAU
#	Updated to use http get instead of direct db access   2007/12/10  RAU
#       2013/05/15       Moved to /opt/amaint/prod/bin;   RU
#                        Modified to use ICATCredentials  RU
#	

use LWP::UserAgent;
use Getopt::Std;
use lib '/opt/amaint/prod/lib';
use Amaintr;
use ICATCredentials;

use constant PRINTCMD => 0;

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

my $cred = new ICATCredentials('amaint.json') -> credentialForName('getcl');
my $TOKEN = $cred->{'token'};
my $BASEURL = $cred->{'url'};

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
$yearsem = $year + 1900;
print("yday:$yday\n") if $main::TEST;
if ($yday < 40) { $sem = 1; $yearsem.='1'; }
elsif (90 < $yday && $yday < 161) { $sem = 4; $yearsem.='2'; }
elsif (210 < $yday && $yday < 283) { $sem = 7; $yearsem.='3'; }
elsif ($yday > 334) { $year++; $yearsem++; $sem = 1; $yearsem.='1'; }
else { exit(0); }
$semester = $year.$sem;
print "Class numbers for semester $semester ($yearsem)\n";

my $url = "${BASEURL}enrollmentCount?semester=" . $semester . "&token=$TOKEN";
print $url."\n" if $main::TEST;
my $response = getFromURL($url);
my $lines = 0;
my $line = '';
my $lastcrse = "";

foreach $line (split /\n/,$response) {
	my ($crsename, $crsenum,$section,$count) = split /,/,$line;
	my $course = $crsename.$crsenum;

	if ($lines == 0) {
		print( "\nCourse   Section   Current\n" );
		print( "                   Enrollment\n" );
		print( "-------  -------   ----------\n" );
	}
	elsif ($crsename ne $lastcrse) {
		print("\n" );
	}
	printf( "%-8.8s   %-4s      %5.5s\n", $course, $section, $count );
	$lastcrse = $crsename;
	$lines++;
}
exit 0;


sub getFromURL {
   my ($url) = @_;
   my $i = 0;
   my $ua = LWP::UserAgent->new;
   $ua->timeout(180);
GET:
   for (;;) {
     last if $i++==4;
     print "$url\n" if PRINTCMD;
     my $response = $ua->get($url);
     if ($response->is_success) {
       return $response->content;
     }
     printf( "Get for $url not successful" );
     sleep 30;
     next GET;
   }
   return "";
}

sub _stderr($) {
    my ($line) = @_;

    print STDERR scalar localtime() . " $line\n";
}


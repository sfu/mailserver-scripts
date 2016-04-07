#!/usr/local/bin/perl
# updtpb.pl : A program which updates the phonebook data in the Amaint db.
#             It reads raw phone data from stdin, in the format produced by 
#             the Call Data Report (CDR) system. (See updatePhonebook.sh script).
#             Then does a POST of the CDR data to a DA in Amaintr.
#
# usage: loadpb.pl -tvn
#             -t Test mode. 
#             -n No DB. Just prints the phone book data; doesn't update the db.
#             -v Verbose mode. Use this with -t flag to get lots of output.
#
#
# Rob Urquhart    Feb 7, 2012
# Changes
# -------
#   Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU
#

use Getopt::Std;
use XML::Simple;
use LWP;

$THEFILE = "$LOCKERDIR/locker.0";
#
# THis token contains a wildcard ip
#
$main::TOKEN = '3w2SzeyZ5JfWQBnKsJ.3lNsOVU1XsTuFv8t0.YdTUvPuUl6df3e6Ig';
#
# This token contains rm-rstar's ip address 142.58.101.21
#
#$main::TOKEN = '6cGsP45MXre4NY5gcDKMkISgIszbsUeGaKQJFtc7zHpzxYfgB1Abng';
#
# Service url for testing
#
#$main::SERVICEURL = "https://mystage.sfu.ca/cgi-bin/WebObjects/praetorian.woa/ws/soaphandler";
#$main::SERVICEURL = "http://icat-rob-macpro.its.sfu.ca/cgi-bin/WebObjects/praetorian.woa/-55099/wa/updatePhonebook?token=".$main::TOKEN;
#
# Service url for prod
#
$main::SERVICEURL = "https://amaint.sfu.ca/cgi-bin/WebObjects/AmaintRest.woa/wa/updatePhonebook?token=".$main::TOKEN;
use constant AC       => '778';
use constant OLDXC1   => '291';
use constant OLDXC2   => '268';
use constant NEWXC    => '782';

@nul = ('not null','null');
select(STDOUT); $| = 1;         # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('tnv') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;
$main::NODB = $opt_n ? $opt_n : 0;
$main::VERBOSE = $opt_v ? $opt_v : 0;

# load phonebook data from STDIN into an array

my $ref = XMLin('-'); 
my $entries = $ref->{PhoneBookEntry};
foreach $entry (@$entries) {
  $sn = $entry->{SURNAME};
  $gn = $entry->{FIRST_NAME};
  $sfuid = $entry->{SFU_ID};
  $ac = $entry->{AREA_CODE_NO};
  $xc = $entry->{EXCHANGE_NO};
  $local = $entry->{LOCAL_NO};
  next if ref($ac) eq 'HASH';
    my $number = _getPhoneNumber($ac, $xc, $local);
    if ($number) {
       $id++;
       push @main::array, "$sn\t$id\t$sfuid\t$number";
    }
}

@array = sort { lc($a) cmp lc($b) } @array;
die("Doesn't look like complete phone book data.\nLast entry is:$main::array[$#main::array]\n") unless _completePhonebookData();

if ($main::NODB) {
    my $entry;
	foreach $entry (@main::array) {
	   print "$entry\n";
	}
	exit 0;
}

$main::numbers = "cdrData=";
foreach $entry (@main::array) {
    my ($sn,$id,$sfuid, $num) = split /\t/,$entry;
     $main::numbers .=  "$sfuid:$num\n";
}
chomp $main::numbers; # remove the newline;

print ($main::numbers) if $main::TEST;
# Send the data to Amaint REST service

my $req = HTTP::Request->new( 'POST', $main::SERVICEURL );
$req->header( 'Content-Type' => 'application/x-www-form-urlencoded' );
$req->content( $main::numbers );
my $lwp = LWP::UserAgent->new;
my $response = $lwp->request( $req );
if ($response->is_success) {
   my $content = $response->decoded_content;
   if ($content =~ /^err /) {
      print STDERR "error result\n";
      print STDERR $content . "\n";
      exit(-3);
   }
}
else {
   print STDERR $response->status_line, "\n";
}
   

exit 0;

sub _completePhonebookData() {
    my $size = $#main::array;
    return 0 if $size==-1;
    return 1 if $main::array[$size]=~/^[zZ]/;
    return 0;
}

sub _getPhoneNumber {
   my ($ac, $xc, $local) = @_;
   $ac = AC unless $ac;
   $ac = '778' if $ac eq '77';
   print("ac:$ac xc:$xc local:$local\n") if $main::TEST && $main::VERBOSE;
   $xc = _getExchange( $local ) unless $xc;
   print("Exchange:$xc\n") if $main::TEST && $main::VERBOSE;
   return '' unless $xc;
       
   if (length($local)==5) {
      $local = substr($local,1,4);
   }
   return '' if (length($local)!=4);
   return "1 ".$ac." ".$xc."-".$local;
}

sub _getExchange {
   my ($local) = @_;
   return '' unless $local;
   my $xc = '';
   
   my $firstDigit = substr($local,0,1);
   if (length($local)==5) {
      if ($firstDigit == 2) { 
         $xc = NEWXC;
      } else {
         return '';
      }
   } elsif (length($local) == 4) {
      $xc = ($local < 6000) ? OLDXC1 : OLDXC2;
   } else { return ''; }
   return $xc;
}

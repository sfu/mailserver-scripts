#! /usr/local/bin/perl -w
#

use Socket;
use Getopt::Std;
use LWP;
use lib '/opt/mail/maillist2/bin';
use LOCK;
use MLUtils;
#require 'getopts.pl';
#use vars qw($main::MLDIR $main::TOKEN $main::SERVICE $opt_h $opt_a);

select(STDOUT); $| = 1;         # make unbuffered

$main::LOGFILE = "/opt/mail/maillist2/logs/mlupdt.log";
open STDOUT, ">>${main::LOGFILE}" or die "Can't redirect STDOUT";
open STDERR, ">&STDOUT" or die "Can't dup STDOUT";

my %activeMaillistHash = &getAllActiveMaillists();
my @localMaillistArray = &getLocalMaillists();

foreach my $maillistDir (@localMaillistArray) {
       if ( !$activeMaillistHash{$maillistDir} && !($maillistDir =~ /\./) ) {
               $maillistDir =~ s/\&/\\\&/g;
               next unless $maillistDir;
               next if index($maillistDir, " ") > -1;
               next if index($maillistDir, "\t") > -1;
               next if index($maillistDir, "-") == -1;
               next if substr($maillistDir, 0, 1) eq ' ';
               _stdout( "Deleting inactive \'$maillistDir\'" );
               `rm -f /opt/mail/maillist2/files/$maillistDir/allow`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/deny`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/maillist.dir`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/maillist.pag`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/members`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/deliveryList`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/ts`;
               `rm -f /opt/mail/maillist2/files/$maillistDir/acl` if -e "/opt/mail/maillist2/files/$maillistDir/acl";
               `rm -f /opt/mail/maillist2/files/$maillistDir/maillist.txt` if -e "/opt/mail/maillist2/files/$maillistDir/maillist.txt";
               `rmdir /opt/mail/maillist2/files/$maillistDir`;
       }
}

sub getAllActiveMaillists {
my $list = '';
my %activeList = ();

       my $url = "https://my.sfu.ca/cgi-bin/WebObjects/ml2.woa/wa/getListNames?token=$token";
       print "Getting $url" if $main::TEST;
       my $mldata = '';
       my $ua = LWP::UserAgent->new;
       $ua->timeout(90);
       my $getcounter = 0;
GET:
       for (;;) {
         $getcounter++;
     # ua->get catches the die issued by the SIGTERM handler, so
     # I have the handler set MLD::TERM, then test it after the call to get.
     $TERM = 0;
     my $response = $ua->get($url);
     if ($response->is_success) {
       $main::sleepCounter = 0;
       $mldata = $response->content;
       last;
     }
     die "interrupted" if $TERM;
     _stdout( "get for $url not successful:". $response->code . " : " .  $response->status_line . "\n" . $response->error_as_HTML  );
     if ($getcounter == 4) {
       _stdout( "get for $url failed 4 times. Exiting." );
       exit(0);
     }
     _sleep();
     next GET;
  }
       my @LISTS = split /\n/,$mldata;
       die "Active maillist sanity check failed!" if $#LISTS < 30000;
       foreach $list (@LISTS) {
            $list =~ s/^\s+//;
            $list =~ s/\s+$//;
            my ($listname,$timestamp) = split /\t/, $list;
            $activeList{$listname} = $listname;                       
       }
return %activeList;        
}

sub getLocalMaillists {
my $maillistDir = "/opt/mail/maillist2/files";
       my @LIST = ();
       opendir my($dh), $maillistDir or die ("Couldn't open '$maillistDir': $!\n");
       my @localMaillistDir = readdir $dh;
       closedir $dh;
        foreach $list (@localMaillistDir) {
            $list =~ s/^\s+//;
            $list =~ s/\s+$//;
            push @LIST, $list;
        }
        return @LIST;
}


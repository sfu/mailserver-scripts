#!/usr/bin/perl
#
# Run through test delivery. Doesn't actual deliver message but does output lots of debug output
# Use mlqtest.pl to create a test queued message, then pass in the name of the temp queue dir created in /tmp/mlqueue as the first argument
use lib '../../lib';
use MLDtest;
use MLMail;
use MLCachetest;
select(STDOUT); $| = 1;         # make unbuffered

$main::TEST=1;
$main::DELIVER=0;
$main::QUEUEDIR='/tmp/mlqueue';
#$listname = shift @ARGV;
#$address = shift @ARGV;
$dir = shift @ARGV;

processMessage( $dir );


#$maillist = new MLCachetest($listname);
#print "allowedToSend: ".$maillist->allowedToSend($address)."\n";
#exit 0 unless $maillist->allowedToSend($address) eq 'SEND';
#my $path = '/tmp/mlqueue/'.$dir;
#open $main::MSG, "$path/msg";
#my $msg  = Mail::Internet->new( $main::MSG, MailFrom => "IGNORE" );
#getRecipients($address, $path, $msg);
#&printRecipientsHash;

#!/usr/local/bin/perl
#
use lib '/opt/mail/maillist2/bin';
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

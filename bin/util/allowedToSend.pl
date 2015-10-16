#!/usr/local/bin/perl
#
use lib '/opt/mail/maillist2/bin';
use MLD;
use MLMail;
use MLCache;
select(STDOUT); $| = 1;         # make unbuffered

$listname = shift @ARGV;
$address = shift @ARGV;
#my @addrs = qw( foo@bar.com robert@gmail.com rob_urquhart@sfu.ca frances.atkinson@mail.sfu.ca urquhart@sfu.ca ic-info@sfu.ca owner-ic-info@sfu.ca);
#foreach $addr (@addrs) {
#   print "$addr:".canonicalAddress($addr)."\n";
#}

$main::TEST = 1;
$maillist = new MLCache($listname);
#$maillist = new MLCachetest($listname);
print "allowedToSend: ".$maillist->allowedToSend($address)."\n";
#if ($maillist->isManager($address)) {
#   print "yes\n";
#} else {
#   print "no\n";
#}
#$list = $maillist->deliveryList();
#print $list."\n";


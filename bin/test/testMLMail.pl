#!/usr/local/bin/perl
use Getopt::Std;
use lib "/opt/mail/maillist2/bin/test";
use MLMail;

my $name = shift;
#$main::TEST = 1;

print "rob\@sfu.ca ";
print hasSFUDomain("rob\@sfu.ca") ? "is" : "is not";
print " an SFU domain.\n";
print "rob\@cs.sfu.ca ";
print hasSFUDomain("rob\@cs.sfu.ca") ? "is" : "is not";
print " an SFU domain.\n";
print "rob\@sfu.ca.us ";
print hasSFUDomain("rob\@sfu.ca.us") ? "is" : "is not";
print " an SFU domain.\n";
print "Canonical address for robert\@sfu.ca: ". canonicalAddress("robert\@sfu.ca")."\n";
print "Canonical address for rob.urquhart\@sfu.ca: ". canonicalAddress("rob.urquhart\@sfu.ca")."\n";
print "Canonical address for bartadm\@sfu.ca: ". canonicalAddress("bartadm\@sfu.ca")."\n";
print "Canonical address for bartadm\@purcell.ais.sfu.ca: ". canonicalAddress("bartadm\@purcell.ais.sfu.ca")."\n";
print "Canonical address for gparker\@cs.sfu.ca: ". canonicalAddress("gparker\@cs.sfu.ca")."\n";
print "Canonical address for gparker\@stat.sfu.ca: ". canonicalAddress("gparker\@stat.sfu.ca")."\n";
print "isLocalAddress(rob.a.urquhart\@gmail.com) = " .isLocalAddress("rob.a.urquhart\@gmail.com")."\n";

exit 0;

sub _stdout($) {
    my ($line) = @_;

    print STDOUT scalar localtime() . " $line\n";
}

sub _stderr($) {
    my ($line) = @_;

    print STDERR scalar localtime() . " $line\n";
}


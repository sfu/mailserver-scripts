#!/usr/local/bin/perl
use lib '/opt/amaint/prod/lib';
use Amaintr;
use Utils;
use ICATCredentials;

#
# Initiate sending of warning messages
# This just invokes a DA in Amaint which sends the messages.
# See the amaint crontab for scheduling.
#

my $cred = new ICATCredentials('amaint.json') -> credentialForName('amaint');
my $TOKEN = $cred->{'token'};
my $amaintr = new Amaintr( $TOKEN, 0 );

my $result = $amaintr -> fireWarnings();
if ($result =~ /^err /) {
   _stderr($result);
}
exit 0;



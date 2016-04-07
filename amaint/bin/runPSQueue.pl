#! /usr/local/bin/perl
#
# runPSQueue : A program which runs the PS message queue to publish
#              any unpublished messages.
#
# Rob Urquhart    Oct 22, 2003
# Changes
# -------
#   Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU
#       

use lib '/opt/amaint/prod/lib';
use Amaintr;
use ICATCredentials;

@nul = ('not null','null');
select(STDOUT); $| = 1;         # make unbuffered

my $cred = new ICATCredentials('amaint.json') -> credentialForName('psqueue');
my $TOKEN = $cred->{'token'};
my $amaintr = new Amaintr( $TOKEN, 0 );

$result = $amaintr->runPSQueue();
if ($result =~ /^err /) {
   _stderr("Error running PS Queue: $result");
}
exit 0;


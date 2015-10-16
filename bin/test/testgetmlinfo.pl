#! /usr/local/bin/perl -w
#
# mlupdate.pl : A program run via inetd and/or cron to update the maillist 
#                files.
#
# Add to inetd.conf as:
# mlupdate      stream  tcp     nowait  amaint  /path/to/mlupdate.pl    mlupdate
# Add to services:
# mlupdate 6087/tcp
#
# Rob Urquhart    Jan 15, 2007
# Changes
# -------
#       

use Socket;
use SOAP::Lite ;
use Getopt::Std;
use lib '/opt/mail/maillist2/bin';
use LOCK;
use MLUtils;
use MLUpdt;
require 'getopts.pl';
use vars qw($main::MLDIR $main::TOKEN $main::SERVICE $opt_h $opt_a);

select(STDOUT); $| = 1;         # make unbuffered
$SIG{INT}  = 'IGNORE';
$SIG{HUP}  = 'IGNORE';
$SIG{QUIT} = 'IGNORE';
$SIG{PIPE} = 'IGNORE';
$SIG{STOP} = 'IGNORE';
$SIG{ALRM} = 'IGNORE';
$SIG{TERM} = 'IGNORE';

$main::MLROOT = "/opt/mail/maillist2";
$main::TEST = 1;
$main::MLROOT = "/tmp/maillist2" if $main::TEST;
#$main::LOGFILE = "${main::MLROOT}/logs/mlupdt.log"; 
#open STDOUT, ">>${main::LOGFILE}" or die "Can't redirect STDOUT";
#open STDERR, ">&STDOUT" or die "Can't dup STDOUT";
$main::MLDIR = "${main::MLROOT}/files";
#$main::UPDATEALL_LOCK = "${main::MLROOT}/mlupdate-a.lock";

if ($main::TEST) {
        $main::SERVICEURL = "http://icat-rob-macpro.its.sfu.ca:60666/cgi-bin/WebObjects/Maillist.woa/ws/MLWebService";
        _stdout( "MLROOT: ${main::MLROOT}\n" );
        unless (-e $main::MLROOT) {
                mkdir $main::MLROOT;
                mkdir "${main::MLROOT}/logs";
                mkdir "${main::MLROOT}/files";
        }
}

$main::listname = shift @ARGV;
if ($main::listname) {
    # script is being run from command-line with a supplied listname.
    my $MLINFO = getmlinfo($listname);
    if (defined $MLINFO) {
        my $ml = $MLINFO->{maillist};
        foreach $key (keys %{$ml}) {
                        $ml->{$key} = '' unless defined $ml->{$key};
                        print "$key:".$ml->{$key}."\n";
        }
    }
}

exit 0;

sub getmlinfo {
        my $listname = shift;
        my $result = '';
        my $SERVICE = SOAP::Lite
        -> ns_uri( $main::SERVICEURL )
        -> proxy( $main::SERVICEURL );

        $MLUpdt::TERM = 0;
        _stderr("getMLInfo for $listname");
        eval { $result = $SERVICE -> getMLInfo( $main::SOAPTOKEN, $listname); };
        _stderr("Back from getMLInfo for $listname");
        if ($MLUpdt::TERM) {
                $! = "interrupted";
                return undef;
        }
        if ($@) {
            _stderr( "%s eval failed for getMLInfo for list $listname:$!" );
            _stderr( $@ );
            return undef;
        }
        if ($result->fault) {
           _stderr( $result->fault );
           return undef;
        }
        my $info = $result->result();
        if ($info =~ /^err /) {
           _stderr($info);
           return undef;
        }
        return $info;
}


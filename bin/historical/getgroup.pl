#! /usr/local/bin/perl
#
# getgroup.pl : A program to extract nis 'group' file information
#	    from Amaint and use it to build a set of NIS group maps.
#
# Changes
# -------
#

use Getopt::Std;
use lib '/opt/amaint/prod/lib';
use NisGroup;
use Utils;
require 'getopts.pl';

@nul = ( 'not null', 'null' );
select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

NisGroup::build_map();
exit(0);

#
#	Local subroutines
#

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}

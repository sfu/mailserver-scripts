#! /usr/local/bin/perl
#
# getusers.pl : A program to convert student/staff id #s into logins.
#
# Robert Urquhart       8 Oct 1996
# Useage: ./getusers.pl filename > filename.out
# Then in maillist do
# mod easc-undergrads members filename.out
#  Changes
#  -------
#	Converted to perl5 and sybperl2
#  02/27/2002 Ignore blank lines and lines that start with "#" in input.
#

# The following variables define NIS and other locations.
$THEFILE = "/opt/adm/amaint/locker.0";

use Sybase::DBlib;
require 'getopts.pl';

@nul = ('not null','null');
$ENV{PATH}="";

select(STDOUT); $| = 1;         # make unbuffered

#
# Log us in to Sybase.
#

$SIG{'INT'} = 'EXITHANDLER';
$SIG{'HUP'} = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';


open( FILL, "<$THEFILE" );
$thestr=<FILL>;
who: for $jael (-9276, -8751, -24125, -6161, -9739, -2351, -15396, -6669, -15390, -11054, -8285, -7771, -2361, -23596, -15372, -23645)
{ if ($i < length($thestr)) { substr($thestr,$i,1) = sprintf( "%c", ((($jael/256)%256-1)^ord(substr($thestr,$i,1)))); }
  else { last who; } $i++;
  if ($i < length($thestr)) { substr($thestr,$i,1) = sprintf( "%c", (($jael%256)^ord(substr($thestr,$i,1)))); }
  else { last who; } $i++;
} 
$slf=index($thestr,"/");
$dbh = new Sybase::DBlib substr($thestr,0,$slf), substr($thestr,$slf+1), "AMAINT";
$thestr="                              ";

$status = $dbh->dbuse("amaint");
$status = dbmsghandle("msghandler");

while(<>) {
	chomp;
        next if /^\s*$/;
        next if /^\s*#/;
	$dbh->dbcmd( "Select username from people p, logins l ");
	$dbh->dbcmd( "where p.id=l.owner and p.external_id#='$_' ");
	$dbh->dbcmd( "and p.type in ('undergrad','grad') ");
#	$dbh->dbcmd( "and l.acct_status='active'");
	$dbh->dbsqlexec;
	$dbh->dbresults;
	@dat = $dbh->dbnextrow;

	if ($dat[0]) {
		print "$dat[0]\n";
	}
}

&dbexit;
exit 0;

sub EXITHANDLER {
	system 'stty', 'echo';
	print "\n\nAborted.";
	&dbexit;
	exit 1;
}

sub msghandler {
	local( $msgprocess, $msgno, $msgstate, $severity, $msgtext, $srvname, $procname, $procline ) = @_;
    
	if ( $msgno == 1205 ) {
		$deadlock = 1;
	}
	else {
		print "Msg $msgno, Level $severity, State $msgstate.\n";
	}
        
	0;
}



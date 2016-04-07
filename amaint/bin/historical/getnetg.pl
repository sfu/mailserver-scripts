#! /usr/local/bin/perl
#
# getnetg.pl <machine_name>: A program to extract 'netgroup' file information
#	    from Sybase and use it to build a set of NIS password maps.
#
# - Richard Chycoski, 1 April 1993.
#
# There is an extension to the format of the netgroup file:
# Any entries for the 'staff', 'faculty', or 'grad' groups will be automatically
# inserted into indexed groups (e.g. 'staff30'), which will be combined into
# a supergroup (e.g. 'staff') at the end. This also implies that you can have
# multiple entries in the 'static' file for these supergroups. If you wish to
# manually add entries to the staff, faculty, or grad groups, just include as
# many lines of the following format as necessary:
#
# staff (-,someid,domain)
#
# Changes
# -------
# 	Exit if the nis lock is on. 				94/08/15  RAU
#	Added pay-only, pay-too, and exempt netgroups.		94/10/01  RAU
#	Check netg_build_in_progress flag and exit if it is set.94/11/01  RAU
#	Don't include disabled accounts in netgroups.		94/11/18  RAU
#   Add another static file for modem controls.			95/08/17  RAC
#   Fixed netgroup membership recursion and put all user entries
#   in ".*" domains instead of "sfu.ca".			95/08/26  RAC
#   Added a cmpt102 group for beaufort access.			96/03/08  RAU
#   Added linglab netgroup for PC access in the Linguistics Lab.97/01/07 RAC
#	Added other netgroup for type 'O' account access.	97/02/13 RAU
#	Added lock file.					97/03/20 RAU
#	Added deadlock handling to all db accesses.		97/03/20 RAU
#	Use perl5 and sybperl 2, and Amaint.pm.			98/04/01 RAU
#   Updated for Paths.pm module.                        99/07/13  RAU
#   Updated for Single-ID changes.                    2007/03/27  RAU
#   Use SOAP calls instead of direct db access.     2007/10/05  RAU
#   Changed low water mark from 15000 to 13000      2008/01/02  JMR
#   Removed creation of external modem groups       2008/04/17  RAU
#   Copied from Seymour to rm-rstar1 (new NIS master)		2010/02/20 SH
#	- Disabled checking/clearing flag in Amaint (just rebuild every time)
#	- changed hardcoded 'seymour' to 'rm-rstar1'
#   Use Amaintr.pm instead of SOAP service.         2013/05/15 RAU
#	

use Getopt::Std;
use lib '/opt/amaint/prod/lib';
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Paths;

@nul = ('not null','null');
select(STDOUT); $| = 1;		# make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';


$YPDOMAIN = "sfu.ca";
$THEFILE = "$LOCKERDIR/locker.0";
$NETGROUPSTAT = "$YPSRCDIR/netgroup.static";
$NETGROUPMODEMCTL = "$YPSRCDIR/netgroup.modemctl";
$LOCKFILE = "$LOCKDIR/netgroup.lock";	

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;
$YPDIR = "/tmp/sfu.ca" if $main::TEST;

$staffgroups   = 0;
$facultygroups = 0;
$gradgroups    = 0;
$othergroups    = 0;
$paytoogroups  = 0;
$payonlygroups = 0;
$payexemptgroups = 0;
$linglabgroups = 0;
$externgroups = 0;
$cmpt102groups = 0;

$staffsize   = 0;
$facultysize = 0;
$gradsize    = 0;
$othersize    = 0;
$paytoosize  = 0;
$payonlysize = 0;
$payexemptsize = 0;
$linglabsize = 0;
$externsize = 0;
$cmpt102size = 0;

$MAXGROUPSIZE  = 975;
$USERLOWWATER  = 13000;
$MODEMLOWWATER = 12000;

#print STDERR "getnetg.pl starting\n";

acquire_lock( $LOCKFILE );

my $cred = new ICATCredentials('amaint.json') -> credentialForName('getnetg');
my $TOKEN = $cred->{'token'};
my $amaintr = new Amaintr($TOKEN, $main::TEST);

# Clean out any existing temporary YP map.
unlink "$YPDIR/netgroup.tmp.dir","$YPDIR/netgroup.tmp.pag";
unlink "$YPDIR/netgroup.byhost.tmp.dir","$YPDIR/netgroup.byhost.tmp.pag";
unlink "$YPDIR/netgroup.byuser.tmp.dir","$YPDIR/netgroup.byuser.tmp.pag";

# Open the temporary maps.
dbmopen(%NETGROUP,"$YPDIR/netgroup.tmp",0600) || die "Can't open netgroup map $YPDIR/netgroup.tmp.";
dbmopen(%NETGROUPBYHOST,"$YPDIR/netgroup.byhost.tmp",0600) || die "Can't open netgroup map $YPDIR/netgroup.byhost.tmp.";
dbmopen(%NETGROUPBYUSER,"$YPDIR/netgroup.byuser.tmp",0600) || die "Can't open netgroup map $YPDIR/netgroup.byuser.tmp.";

open( NETGROUPSTATIC, "<$NETGROUPSTAT" ) || die "Can't open netgroup 'static' file $NETGROUPSTAT.";

while(<NETGROUPSTATIC>)
{

    chop;
    @fields = split(' '); # Extract fields from each line of the static file.
    for ($i=1; $i < @fields; $i++)
    {
	if ( $fields[$i] =~ /^[^\(]/ ) 			# ..then we have a subgroup.
	{	    
	    if ( $REFERENCES{$fields[$i]} ) 		# ...then we are appending to an existing field.
	    {
	        $REFERENCES{$fields[$i]} .= ",$fields[0]";
	    }
	    else
	    {
	        $REFERENCES{$fields[$i]} = "$fields[0]";
	    }
	}
    }
}

seek( NETGROUPSTATIC, 0, 0 ); # Rewind the static file.

open( NETGROUPMODEMS, "<$NETGROUPMODEMCTL" ) || die "Can't open netgroup 'modem' file $NETGROUPMODEMCTL.";

while(<NETGROUPMODEMS>)
{

    chop;
    @fields = split(' '); # Extract fields from each line of the static file.
    for ($i=1; $i < @fields; $i++)
    {
	if ( $fields[$i] =~ /^[^\(]/ ) 			# ..then we have a subgroup.
	{
	    if ( $REFERENCES{$fields[$i]} ) 		# ...then we are appending to an existing field.
	    {
	        $REFERENCES{$fields[$i]} .= ",$fields[0]";
	    }
	    else
	    {
	        $REFERENCES{$fields[$i]} = "$fields[0]";
	    }
	}
    }
}

seek( NETGROUPMODEMS, 0, 0 ); # Rewind the static file.

# Debug.
#while(($key,$val) = each %REFERENCES)
#{
#    print $key, ": ", $val, "\n";
#}

$modtime=sprintf("%010d", time);
$NETGROUP{"YP_LAST_MODIFIED"} = $modtime;
$NETGROUP{"YP_MASTER_NAME"} = $YPMASTER;

$NETGROUPBYHOST{"YP_LAST_MODIFIED"} = $modtime;
$NETGROUPBYHOST{"YP_MASTER_NAME"} = $YPMASTER;

$NETGROUPBYUSER{"YP_LAST_MODIFIED"} = $modtime;
$NETGROUPBYUSER{"YP_MASTER_NAME"} = $YPMASTER;

# Process the static entries first.

while(<NETGROUPSTATIC>)
{
    chop;

    &process_aliases( $_ );
}

close NETGROUPSTATIC;

while(<NETGROUPMODEMS>)
{
    chop;

    &process_aliases( $_ );
}

close NETGROUPMODEMS;

# Get the netgroup file information for the users from the account maintenance database.
#    print "Getting the netgroup file information for the users.\n";
my $count = 0;
my $rows = $amaintr->getNetgroup();
foreach $row (split /\n/,$rows) {
	($username, $acctclass) = split /:/,$row;
	# Translate acctclass into the appropriate group.
	if    ($acctclass =~ /^staff/) { $ingroup = "staff"; }
	elsif ($acctclass =~ /^faculty/) { $ingroup = "faculty"; }
	elsif ($acctclass =~ /^grad/) { $ingroup = "grad"; }
	elsif ($acctclass =~ /^other/) { $ingroup = "other"; }
	elsif ($acctclass =~ /^external/) { $ingroup = "extern"; }
	else { next; } 	# Don't bother with the others.
	&process_aliases( "$ingroup \(-,$username,\)" );	# RAC 95 Aug 26
	$count++;
}
if ($count<$USERLOWWATER) {
    print "User entries less than low water mark:$count.\n";
	dbmclose( NETGROUP );
    dbmclose( NETGROUPBYHOST );
    dbmclose( NETGROUPBYUSER );
	&cleanexit;
}

# Build the supergroups:

&build_supergroup( "staff", $staffgroups );
&build_supergroup( "faculty", $facultygroups );
&build_supergroup( "grad", $gradgroups );
&build_supergroup( "other", $othergroups );
&build_supergroup( "extern", $externgroups );

dbmclose( NETGROUP );
dbmclose( NETGROUPBYHOST );
dbmclose( NETGROUPBYUSER );

# Debugging exit.
&cleanexit if $main::TEST;

# Move the temporary maps to their permanent places.
open(JUNK, "mv $YPDIR/netgroup.tmp.dir $YPDIR/netgroup.dir|" );
open(JUNK, "mv $YPDIR/netgroup.tmp.pag $YPDIR/netgroup.pag|" );

open(JUNK, "mv $YPDIR/netgroup.byhost.tmp.dir $YPDIR/netgroup.byhost.dir|" );
open(JUNK, "mv $YPDIR/netgroup.byhost.tmp.pag $YPDIR/netgroup.byhost.pag|" );

open(JUNK, "mv $YPDIR/netgroup.byuser.tmp.dir $YPDIR/netgroup.byuser.dir|" );
open(JUNK, "mv $YPDIR/netgroup.byuser.tmp.pag $YPDIR/netgroup.byuser.pag|" );


# Until we get the 'static' data into the database, we must push these
# files out to the other NIS servers manually. - RC 12 Jul 93
open(JUNK, "$YPPUSHCMD -d $YPDOMAIN netgroup|" );
open(JUNK, "$YPPUSHCMD -d $YPDOMAIN netgroup.byhost|" );
open(JUNK, "$YPPUSHCMD -d $YPDOMAIN netgroup.byuser|" );

release_lock( $LOCKFILE );
exit 0;


#
#	Local subroutines
#

# A recursive subroutine to dereference netgroups. RAC - 95 Aug 26
sub deref_group
{
	local( $thegroup ) =@_;
	local( $addtogroups, $subgroups, @subgroups, $i );
	
    @subgroups = split(',',$REFERENCES{ $thegroup });

	$addtogroups = $thegroup;
	
	$nsg=@subgroups;
	for ($i=0; $i < @subgroups; $i++)
	{
		if ( $REFERENCES{ $subgroups[$i] } ) 			 # then include the sub references.
		{
			$addtogroups .= "," . &deref_group( $subgroups[$i] ); # Used only in byuser and byhost tables.
		}
		else
		{
			$addtogroups .= "," . $subgroups[$i];
		}
	}
	return $addtogroups;
}


sub process_aliases
{
    local( $inalias ) = @_;
    local( $fields, $addtogroups, $subfields, $triple, $subgroup, $i );

    @fields = split(' ',$inalias);
    ( $thegroup, $theentry )= split(' ',$inalias,2);

    	$addtogroups = &deref_group( $thegroup ); # Recursively add to groups.

    if ($thegroup =~ /^staff|faculty|grad|other|external_pay_too|external_pay_only|external_exempt|linglab|cmpt102|extern$/) # ...then it's a user. Don't make a simple netgroup map entry.
    {

	for ($i=1; $i < @fields; $i++)
	{
	    $subgroup = &get_a_group( $thegroup, $fields[$i] ); # Get a numbered subgroup to add to.
	    
	    if ( $fields[$i] =~ /^\(/ ) 	# ..then we have a triple. (Ignore subgroup entries.)
	    {
		$triple = $fields[$i];
		$triple =~ s/[\(\)]//g;	# Eliminate parens.
		@subfields = split(',',$triple,3);
		$subfields[0] =~ s/^$/*/;
		$subfields[1] =~ s/^$/*/;	# Convert any null fields to asterisks.
		$subfields[2] =~ s/^$/*/;
		unless ( $subfields[1] =~ /^-$/ ) # ...then we need to make a user entry.
		{
		    if ( $NETGROUP{ $subgroup } ) # ...then we are appending to an existing field
		    {
			$! = ""; # Reset the error indicator.
			$NETGROUP{ $subgroup } .= " $fields[$i]";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding to $subgroup in map 'netgroup'.\n" ); }
		    }
		    else
		    {
			$! = "";
			$NETGROUP{ $subgroup } .= $fields[$i];
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding $subgroup to map 'netgroup'.\n" ); }
		    }
    
		    if ( $NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } ) # ...then we are appending to an existing field
		    {
			$! = "";
			$NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } .= ",$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding to $subfields[1].$subfields[2] in map 'netgroup.byuser'.\n" ); }
		    }
		    else
		    {
			$! = "";
			$NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } = "$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding $subfields[1].$subfields[2] to map 'netgroup.byuser'.\n" ); }
		    }
    
		}
		else
		{
		    printf STDERR "Not a valid user entry: %s (contains a host)\n", $fields[$i];
		}
	    }
	    else
	    {
		printf STDERR "Not a valid user entry: %s (not a triple)\n", $fields[$i];
	    }
	}
    }
    else
    {
	$! = "";
	$NETGROUP{$thegroup} = $theentry;
	unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding $thegroup to map 'netgroup'.\n" ); }

	for ($i=1; $i < @fields; $i++)
	{
	    if ( $fields[$i] =~ /^\(/ ) 	# ..then we have a triple. (Ignore subgroup entries.)
	    {
	    	$triple = $fields[$i];
		$triple =~ s/[\(\)]//g;	# Eliminate parens.
		@subfields = split(',',$triple,3);
		$subfields[0] =~ s/^$/*/;
		$subfields[1] =~ s/^$/*/;	# Convert any null fields to asterisks.
		$subfields[2] =~ s/^$/*/;

		unless ( $subfields[0] =~ /^-$/ ) # ...then we need to make a host entry.
		{
		    if ( $NETGROUPBYHOST{ "$subfields[0].$subfields[2]" } ) # ...then we are appending to an existing field
		    {
			$! = "";
			$NETGROUPBYHOST{ "$subfields[0].$subfields[2]" } .= ",$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding to $subfields[0].$subfields[2] in map 'netgroup.byhost'.\n" ); }
		    }
		    else
		    {
			$! = "";
			$NETGROUPBYHOST{ "$subfields[0].$subfields[2]" } = "$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding $subfields[0].$subfields[2] to map 'netgroup.byhost'.\n" ); }
		    }
		}

		unless ( $subfields[1] =~ /^-$/ ) # ...then we need to make a user entry.
		{
		    if ( $NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } ) # ...then we are appending to an existing field
		    {
			$! = "";
			$NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } .= ",$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding to $subfields[1].$subfields[2] in map 'netgroup.byuser'.\n" ); }
		    }
		    else
		    {
			$! = "";
			$NETGROUPBYUSER{ "$subfields[1].$subfields[2]" } = "$addtogroups";
			unless ( $! =~ /^$/ ) { &ERROR_PROC( "Error $! occurred while adding $subfields[1].$subfields[2] to map 'netgroup.byuser'.\n" ); }
		    }
		}
	    }
	}
    }
}

# pick out a subgroup to add an entry to.
sub get_a_group
{
    local( $ingroup, $theentry ) = @_;
    
    if ($ingroup =~ /^staff$/) {
		if ( $staffsize < 1 ) {
			$staffgroups++;
			$staffsize = 0;
		}
		elsif ( $staffsize >= $MAXGROUPSIZE ) {
			$staffgroups++;
			$staffsize = 0;
		}
		$staffsize += length( $theentry ) + 1;
		return "staff$staffgroups";
    }
    elsif ($ingroup =~ /^faculty$/) {
		if ( $facultysize < 1 ) {
			$facultygroups++;
			$facultysize = 0;
		}
		elsif ( $facultysize >= $MAXGROUPSIZE ) {
			$facultygroups++;
			$facultysize = 0;
		}
		$facultysize += length( $theentry ) + 1;
		return "faculty$facultygroups";
    }
    elsif ($ingroup =~ /^grad$/) {
		if ( $gradsize < 1 ) {
			$gradgroups++;
			$gradsize = 0;
		}
		elsif ( $gradsize >= $MAXGROUPSIZE ) {
			$gradgroups++;
			$gradsize = 0;
		}
		$gradsize += length( $theentry ) + 1;
		return "grad$gradgroups";
    }
    elsif ($ingroup =~ /^other$/) {
		if ( $othersize < 1 ) {
			$othergroups++;
			$othersize = 0;
		}
		elsif ( $othersize >= $MAXGROUPSIZE ) {
			$othergroups++;
			$othersize = 0;
		}
		$othersize += length( $theentry ) + 1;
		return "other$othergroups";
    }
    elsif ($ingroup =~ /^external_pay_too$/) {
		if ( $paytoosize < 1 ) {
			$paytoogroups++;
			$paytoosize = 0;
		}
		elsif ( $paytoosize >= $MAXGROUPSIZE ) {
			$paytoogroups++;
			$paytoosize = 0;
		}
		$paytoosize += length( $theentry ) + 1;
		return "external_pay_too$paytoogroups";
    }
    elsif ($ingroup =~ /^external_pay_only$/) {
		if ( $payonlysize < 1 ) {
			$payonlygroups++;
			$payonlysize = 0;
		}
		elsif ( $payonlysize >= $MAXGROUPSIZE ) {
			$payonlygroups++;
			$payonlysize = 0;
		}
		$payonlysize += length( $theentry ) + 1;
		return "external_pay_only$payonlygroups";
    }
    elsif ($ingroup =~ /^external_exempt$/) {
		if ( $payexemptsize < 1 ) {
			$payexemptgroups++;
			$payexemptsize = 0;
		}
		elsif ( $payexemptsize >= $MAXGROUPSIZE ) {
			$payexemptgroups++;
			$payexemptsize = 0;
		}
		$payexemptsize += length( $theentry ) + 1;
		return "external_exempt$payexemptgroups";
    }
    elsif ($ingroup =~ /^linglab$/) {
		if ( $linglabsize < 1 ) {
			$linglabgroups++;
			$linglabsize = 0;
		}
		elsif ( $linglabsize >= $MAXGROUPSIZE ) {
			$linglabgroups++;
			$linglabsize = 0;
		}
		$linglabsize += length( $theentry ) + 1;
		return "linglab$linglabgroups";
    }
    elsif ($ingroup =~ /^extern$/) {
		if ( $externsize < 1 ) {
			$externgroups++;
			$externsize = 0;
		}
		elsif ( $externsize >= $MAXGROUPSIZE ) {
			$externgroups++;
			$externsize = 0;
		}
		$externsize += length( $theentry ) + 1;
		return "extern$externgroups";
	}
    elsif ($ingroup =~ /^cmpt102$/) {
		if ( $cmpt102size < 1 ) {
			$cmpt102groups++;
			$cmpt102size = 0;
		}
		elsif ( $cmpt102size >= $MAXGROUPSIZE ) {
			$cmpt102groups++;
			$cmpt102size = 0;
		}
		$cmpt102size += length( $theentry ) + 1;
		return "cmpt102$cmpt102groups";
	}
    else { &ERROR_PROC( "Can't get a subgroup for: $ingroup, $theentry\n" ); } 	# Don't bother with the others.

}


# Build a supergroup:
sub build_supergroup
{
	local( $groupprefix, $groupcount ) = @_;
# Debug
# print "Building supergroup for $groupprefix with count = $groupcount.\n";
	
	if ( $groupcount == 0 ) {
		return;
	}
	
	$biggroup = ""; $biggies = 0;

	for ($i=1; $i <= $groupcount; $i++) {
		if ( length( $biggroup ) == 0 ) {
			$biggroup = "$groupprefix$i";
		}
		else {
			$biggroup .= " $groupprefix$i";
		}

		if ( length( $biggroup ) > $MAXGROUPSIZE ) {
			$biggies++;
			$NETGROUP{ "$groupprefix" . $groupcount+$biggies } = $biggroup;
			$biggroup = "";
		}
	}

	if ( $biggies == 0 ) {
		$NETGROUP{ "$groupprefix" } = $biggroup;
	}
	else  {
		if ( length( $biggroup ) > 0 )	{
		# ...then tidy up the remainder of the current supergroup.
			$biggies++;
			$NETGROUP{ "$groupprefix" . $groupcount+biggies } = $biggroup;
		}

		$realbiggies = 0;  $biggroup = "";
		for ($i=1; $i <= $biggies; $i++) {
			if ( length( $biggroup ) == 0 ) {
				$biggroup = "$groupprefix" . $i+$groupcount ;
			}
			else {
				$biggroup .= " $groupprefix" . $i+$groupcount ;
			}
	
			if ( length( $biggroup ) > $MAXGROUPSIZE ) {
				$realbiggies++;
				$NETGROUP{ "$groupprefix" . $groupcount+biggies+realbiggies } = $biggroup;
				$biggroup = "";
			}
		}

		if ( $realbiggies == 0 ) {
			$NETGROUP{ "$groupprefix" } = $biggroup;
		}
		else {
			if ( length( $biggroup ) > 0 ) {
			# ...then tidy up the remainder of the current supergroup.
				$realbiggies++;
				$NETGROUP{ "$groupprefix" . $groupcount+$biggies+$realbiggies } = $biggroup;
			}

			$biggroup = "";
			for ($i=1; $i <= $realbiggies; $i++) {
				if ( length( $biggroup ) == 0 ) {
					$biggroup = "$groupprefix" . $i+$groupcount+$biggies ;
				}
				else {
					$biggroup .= " $groupprefix" . $i+$groupcount+$biggies ;
				}
	
				if ( length( $biggroup ) > $MAXGROUPSIZE ) {
					&ERROR_PROC( "Too many entries in the $groupprefix group.\n" ); 
				}
			}

			$NETGROUP{ "$groupprefix" } = $biggroup;
		}
	}	    
}


sub ERROR_PROC
{
    local( $errmsg ) = @_;
    printf STDERR $errmsg;

    dbmclose( NETGROUP );
    dbmclose( NETGROUPBYHOST );
    dbmclose( NETGROUPBYUSER );

    unlink "$YPDIR/netgroup.tmp.dir","$YPDIR/netgroup.tmp.pag";
    unlink "$YPDIR/netgroup.byhost.tmp.dir","$YPDIR/netgroup.byhost.tmp.pag";
    unlink "$YPDIR/netgroup.byuser.tmp.dir","$YPDIR/netgroup.byuser.tmp.pag";

    exit 2;
}    


sub cleanexit {
	release_lock( $LOCKFILE );
    exit 1;
}

sub EXITHANDLER  {
    system 'stty', 'echo';
    print "\n\nAborted.";
	&cleanexit;
}


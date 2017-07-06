#!/usr/bin/perl
#
# Fetch resoruce accounts from Zimbra and build flat file for them.
# "getaliases.pl" will read that flat file in when building aliases map
#

use Getopt::Std;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
@nul = ('not null','null');
select(STDOUT); $| = 1;		# make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';


$ALIASFILE = "$MAILDIR/zimbraresources";
$TMPALIASFILE = "$ALIASFILE.new";
$LOCKFILE = "$LOCKDIR/zimbraresources.lock";	# 97/03/20 RAU
$ALIASCMD = "/usr/bin/ssh -l zimbra mailbox1.tier2.sfu.ca /opt/sfu/getresources";
@SANITYCHK = ("loc-sh1003","equip-lcp_planning_calendar-sh1001");	# If any of these accounts aren't found in zmprov output, bail

# Get the aliases information for the active users in Zimbra .

open ( ZMPROV, "$ALIASCMD|") || die "Can't run \"$ALIASCMD\" ";
@zmaliases = <ZMPROV>;
close ZMPROV;

# Sanity check the accounts

$found = 0;
$foundme = 0;
foreach $zm (@zmaliases)
{
	chomp $zm;
	$f = $zm;
	$f =~ s/@.*$//;		# Strip domain 
	foreach $sc (@SANITYCHK)
	{
		$found++ if ($f eq $sc);
	}
}


# Try to get lock
open(LK,">$LOCKFILE.$$");
close LK;
while (!(link("$LOCKFILE.$$","$LOCKFILE")))
{
   sleep (3 * rand());
}

# Process the aliases
open( ALIASES, ">$TMPALIASFILE" ) || die "Can't open tmp resources aliases file: $TMPALIASFILE.\n\n";

foreach $za (@zmaliases) {
	next if ($za !~ /\@sfu.ca$/);		# For now at least, skip anything other than @sfu.ca users
	$za =~ s/@.*$//;		# Strip domain part
	print ALIASES "$za\n";
}
close( ALIASES );

if ($found < scalar(@SANITYCHK))
{
    print "NO: One or more mandatory accounts not found in zimbra aliases. Not updating Aliases."; 
    &cleanexit;
}


# Move the temporary file to its permanent place.
open(JUNK, "mv $TMPALIASFILE $ALIASFILE|" );

unlink("$LOCKFILE.$$" );
unlink($LOCKFILE);
exit 0;

sub cleanexit {
    unlink("$LOCKFILE.$$" );
    unlink($LOCKFILE);
    exit 1;
}

sub EXITHANDLER  {
    system 'stty', 'echo';
    print "\n\nAborted.";
	&cleanexit;
}


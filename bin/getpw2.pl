#!/usr/bin/perl
#
# getpw2.pl <machine_name>: A program to extract 'passwd' file information
#           from Amaint and use it to build a secondary alias file.
#	    This maps to all users in Connect who can receive mail
#
# Changes
# -------
#       Don't build passwd entries for disabled accounts.       94/11/18 RAU
#       Make script work on both catacomb and solaris servers.  96/01/24 RAU
#       Point ypmaster back to seymour.sfu.ca from old-seymour. 96/08/01 RAU
#       Add checkpid subroutine and use it to check lock file.  97/04/07 RAU
#       Updated for perl5 and sybperl 2.                        97/09/11 RAU
#       Updated to use Amaint.pm.                               98/03/30 RAU
#       Updated for Paths.pm module.                            99/07/13 RAU
#       Only include disabled/locked accts if forward flag set. 00/03/06 RAU
#       Set a valid shell if for included disabled accounts.  2004/01/26 RAU
#       Modified to build an Aliases map for the mail gateway 2004/02/16 SH
#       Added a "blockfile" to exclude certain users from     2004/04/07 SH
#          aliases map (makes them "internal only" accounts     
#   	Use SOAP calls instead of direct db access            2007/10/11 RAU
#   	Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU
#	Linux support: Convert from dbm to DB_file, change filenames	2014/01/15 SH
#	Modified to work universally on any core mailserver	2016/04/07 SH

use Getopt::Std;
use Sys::Hostname;
use DB_File;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;

@nul = ('not null','null');
select(STDOUT); $| = 1;         # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

$MAILDIR = "/tmp" if $main::TEST;
$BLOCKFILE = "$MAILDIR/blockfile";
$LOCKFILE = "$LOCKDIR/passwd.lock";             
$ALIASFILE = "$MAILDIR/aliases2";
$TMPALIASFILE = "$ALIASFILE.new";
$EXCHANGEUSERS = "$MAILDIR/exchangeusers";
$ZIMBRARESOURCES = "$MAILDIR/zimbraresources";
$MINCOUNT = 50000;
$EXCLUDES = "wiki|admin|spam.ui5gzd9xy|ham.uzqsnwwk|test1|majordom|maillist"  ;        # Accounts that shouldn't be put into aliases map for Connect
use constant SHELL => "/bin/sh";

# Target mail host for users
# If we're running on mailgw1/2, it's Connect. If we're on a mailgate (pobox) node, it's "mailhost.sfu.ca" (which points to mailgw1/2)
# And if we're on the staging server, point at email-stage
$mailhost = "connect.sfu.ca";
$INTERNAL=1;  # running on an internal mail router
my $hostname = hostname();
if ($hostname =~ /^pobox/)
{
    $mailhost = "mailhost.sfu.ca";
    $INTERNAL=0;
}
elsif ($hostname =~ /stage\.its\.sfu\.ca/)
{
    $mailhost = "email-stage.sfu.ca";
}

exit(0) if lockInUse( $LOCKFILE );
acquire_lock( $LOCKFILE );

if (-f $EXCHANGEUSERS)
{
    open(EXCH,$EXCHANGEUSERS);
    while(<EXCH>)
    {
	chomp;
	($u,$v) = split(/:/);
	$u =~ s/\s+//g;
	$v =~ s/\s+//g;
	$exchange{$u} = $v;
    }
    $have_exchange=1;
    close EXCH;
}

my $cred = new ICATCredentials('amaint.json') -> credentialForName('amaint');
my $TOKEN = $cred->{'token'};

my $amaintr = new Amaintr($TOKEN, $main::TEST);

# Collect list of IDs/aliases that we shouldn't include
if (open (BLOCK, "$BLOCKFILE"))
{
    while (<BLOCK>)
    {
        next if (/^#/);   # skip comment lines
        chomp;
        $blocks{$_} = 1;
    }
    close BLOCK;
}

# Clean out any existing temporary aliases map.
unlink "$MAILDIR/aliases2.tmp", $TMPALIASFILE;

# Get the passwd file information from the account maintenance database.
my $passwd = $amaintr->getPW();

# Open the temporary maps.
tie( %ALIASES, "DB_File","$MAILDIR/aliases2.tmp", O_CREAT|O_RDWR,0644,$DB_HASH )
  || die "Can't open aliases map $MAILDIR/aliases2.tmp.";


open( ALIASESSRC, ">$TMPALIASFILE" ) || die "Can't open aliases source file: ${TMPALIASFILE}.\n\n";

$modtime=sprintf("%010d", time);
$ALIASES{"YP_LAST_MODIFIED"} = $modtime;
$ALIASES{"YP_MASTER_NAME"} = $YPMASTER;

$atsign="@";
$ALIASES{ "$atsign\0" } = "$atsign\0";

my $count=0;
foreach $line (split /\n/,$passwd) {
    ($username, $pw, $uid, $gid, $gcos, $homedir, $shell) = split /:/,$line;
    print "$username:$pw:$uid:$gid:$gcos:$homedir:$shell\n" if $main::TEST;
	if ($INTERNAL)
	{
	    # Certain accounts don't get forwarded to Connect.sfu.ca, even though they're full accounts
	    next if ($username =~ /^($EXCLUDES)$/);
	}
	if ($have_exchange && $exchange{$username}) 
    {
			$ALIASES{"$username\0"} = $exchange{$username}."\0";
			print ALIASESSRC "$username: ",$exchange{$username},"\n";
			$count++;
			next;
	}	
    if (!$blocks{$username}) 
    {
            #   Put entries in the aliases map
            $ALIASES{"$username\0"} = "$username\@$mailhost\0";
            print ALIASESSRC "$username: $username\@$mailhost\n";
    }
    $count++;
}

if (-f $ZIMBRARESOURCES)
{
    open(ZIM,$ZIMBRARESOURCES);
    while(<ZIM>)
    {
	chomp;
	$ALIASES{"$_\0"} = "$_\@$mailhost\0";
	print ALIASESSRC "$_: $_\@$mailhost\n";
    }
}

untie (%ALIASES);

&cleanexit if $main::TEST;  # For debugging

cleanexit("New aliases2 file < low water mark: $count") if $count < $MINCOUNT;


# Move the temporary maps to their permanent places.
open(JUNK, "mv $MAILDIR/aliases2.tmp $MAILDIR/aliases2.db|" );
open(JUNK, "mv $TMPALIASFILE $ALIASFILE|" );

release_lock( $LOCKFILE );

exit 0;

#
#       Local subroutines
#

sub cleanexit {
        release_lock( $LOCKFILE );
        exit 1;
}

sub EXITHANDLER  {
        system 'stty', 'echo';
        print "\n\nAborted.";
        &cleanexit;
}


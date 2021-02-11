#!/usr/bin/perl
#
# getaliases.pl: A program to extract 'aliases' file information from
# Amaint, and use it to build an NIS alias map and a backup text file.
#
# Changes
# -------
#       Check nislock and exit if it is set.                                    94/08/15  RAU
#       Check alias_build_in_progress flag and exit if it is set.94/10/31  RAU
#       If acct is disabled, don't build alias entries.                 94/11/18  RAU
#       Get status when doing alias-to-username mappings.               95/06/29  RAU
#       Remove byaddr maps (not needed for current sendmail) and alter map
#       names to build private maps for mail server instead of NIS maps.95/08/30  RAC
#       Stop including the static aliases (now in a separate map).      95/08/03  RAC
#       Include aliases from the static_aliases table                   96/02/16 RAU
#       Include maillists from the maillist table                               96/07/04 RAU
#       Use lock file instead of db flag                                                97/03/20 RAU
#       Fix deadlock handling code.
#       Updated for perl5 and sybperl 2.                                                97/09/11  RAU
#       Updated for Amaint.pm.                                                                  98/03/31  RAU
#       Updated for use of bulk_mailer for restricted lists.                            98/03/31  RAU
#       Rewrote for use on Mail Gateway. Aliases are all now "alias: alias@mailhost.sfu.ca" 04/02/12 SH
#       Add a "block file" to block aliases that we don't want to appear on the outside
#         (currently the following: rootcsh, rootsh, sysadm, daemon, sys, adm, and lp)
#       Use SOAP service to get alias data.                     2007/10/11 RAU
#       Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU
#	Convert dbm to DB_File for Linux			2014/01/14 SH
#
#	Now one script for both mailgate and core server	2016/04/07 SH

use Getopt::Std;
use DB_File;
use Sys::Hostname;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Paths;
use LWP::Simple;


select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

$ALIASMAPNAME       = "$ALIASESDIR/aliases";
$ALIASFILE          = "$ALIASESDIR/aliases";
$USERMAPNAME        = "$ALIASESDIR/aliases2.db";
$TMPALIASFILE       = "$ALIASFILE.new";
$STATICFILE         = "$ALIASESDIR/staticaliases";
$TMPSTATICFILE      = "$STATICFILE.new";
$SINGLEIDALIASES    = "$ALIASESDIR/singleid_aliases";
$LIGHTWEIGHTALIASES = "$ALIASESDIR/lightweightaliases";
$BLOCKFILE          = "$ALIASESDIR/blockfile";
$LOCKFILE           = "$LOCKDIR/aliases.lock";
$MINCOUNT           = 165000;
if ($main::TEST) {
    $ALIASMAPNAME = "/tmp/aliases";
    $ALIASFILE    = "/tmp/aliases";
    $TMPALIASFILE = "/tmp/aliases.new";
}

$hostname = hostname();
$MAILHOST = undef;
if ($hostname =~ /^pobox/)
{
	$MAILHOST = "mailhost.sfu.ca";
}

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

exit(0) if lockInUse($LOCKFILE);
acquire_lock($LOCKFILE);
my $cred  = new ICATCredentials('amaint.json')->credentialForName('amaint');
my $TOKEN = $cred->{'token'};

my $amaintr = new Amaintr( $TOKEN, $main::TEST );

# Collect list of IDs/aliases that we shouldn't include
if ( open( BLOCK, "$BLOCKFILE" ) ) {
    while (<BLOCK>) {
        next if (/^#/);    # skip comment lines
        chomp;
        push @blocks, $_;
    }
    close BLOCK;
}

open( ALIASESSRC, ">$TMPALIASFILE" )
  || die "Can't open aliases source file: ${TMPALIASFILE}.\n\n";
open( STATIC, ">$TMPSTATICFILE" )
  || die "Can't open static aliases file: ${TMPSTATICFILE}.\n\n";

# Clean out any existing temporary YP map.
unlink "$ALIASMAPNAME.tmp";

# Open the temporary maps.
tie( %ALIASES, "DB_File","$ALIASMAPNAME.tmp", O_CREAT|O_RDWR,0644,$DB_HASH )
  || die "Can't open aliases map $ALIASMAPNAME.tmp.";

# Open the users map.
tie( %USERS, "DB_File","$USERMAPNAME", O_RDONLY,0644,$DB_HASH )
  || die "Can't open users map $USERMAPNAME";

&getAlumni();

$modtime = sprintf( "%010d", time );
$ALIASES{"YP_LAST_MODIFIED"} = $modtime;
$ALIASES{"YP_MASTER_NAME"}   = $YPMASTER;

# Insert the static '@' entry.

$atsign = "@";
$ALIASES{"$atsign\0"} = "$atsign\0";

# Get the aliases file information for the active users from the account maintenance database.

# Process the lightweight aliases

my $count = 0;
open( LIGHTWEIGHT, "<$LIGHTWEIGHTALIASES" )
  || die "Can't open lightweight alias file:${LIGHTWEIGHTALIASES}.\n\n";
while (<LIGHTWEIGHT>) {
    chomp;

    $line = $_;
    # Skip over lightweight accounts that point to Alumni accounts that haven't been set up
    if (/\@alumni.sfu.ca/) {
    	($key,$value) = split(/:/);
    	$value =~ s/\s+//g;
    	$value =~ s/\@.*//;
    	next if (!$ALUMNI{$value});
    }

    &process_alias($line);
    print STATIC "$line\n";
    $count++;
}
close LIGHTWEIGHT;

# Process the Single-ID aliases

open( SINGLEID, "<$SINGLEIDALIASES" )
  || die "Can't open singleid alias file:${SINGLEIDALIASES
}.\n\n";
while (<SINGLEID>) {
    chomp;

    # Skip over "Single ID" aliases (old accounts that were retired when we amalgamated accounts) 
    # that point to accounts that are no longer active
    ($key,$value) = split(/:/);
    $value =~ s/\s+//g;
    $value =~ s/\@.*//;
    next if (!defined($USERS{"$value\0"}));

    &process_alias($_);
    print STATIC "$_\n";
    $count++;
}
close SINGLEID;

# Process the static_aliases table

my $static = $amaintr->getStaticAliases();
if ( $static =~ /^err / ) {
    cleanexit($static);
}
if (length($static)<200) {
    cleanexit("Result from getStaticAliases less than low water mark");
}
foreach $row ( split /\n/, $static ) {
    my ( $alias, $target ) = split /:/, $row;
    $found = 0;
    foreach $block (@blocks) {
        if ( $alias eq $block ) {
            $found = 1;
            last;
        }
    }
    $count++;
    next if $found;
    if (defined($MAILHOST))
    {
	&process_alias("$alias: $alias\@$MAILHOST");
	print STATIC "$alias: $alias\@$MAILHOST\n";
    }
    else
    {
    	&process_alias($row);
    	print STATIC $row . "\n";
    }
    $count++;
}

# Process the alias-to-username mappings for this range

my $users = $amaintr->getAliases();
if ( $users =~ /^err / ) {
    cleanexit($users);
}
if (length($users)<500000) {
    cleanexit("Result from getAliases less than low water mark");
}
foreach $row ( split /\n/, $users ) {
    my ( $alias, $target ) = split /:/, $row;
    
    $target =~ tr/A-Z/a-z/;
    if (!defined($USERS{"$target\0"}) && !defined($ALIASES{"$target\0"}))
    {
        # Amaint sends us all aliases, even for lightweight accounts.
        # Most lightweight accounts don't actually have email, so
        # skip aliases for target accounts that no longer exist
        next;
    }
    if (defined($MAILHOST))
    {
	    &process_alias("$alias: $alias\@$MAILHOST");
    }
    else
    {
    	&process_alias($row);
    }
    $count++;
}

close(STATIC);
close(ALIASESSRC);
untie(%ALIASES);

&cleanexit('test run exiting') if $main::TEST;
cleanexit("New aliases file < low water mark: $count") if $count < $MINCOUNT;

# Move the temporary maps and files to their permanent places.
system("mv $ALIASMAPNAME.tmp $ALIASMAPNAME.db");
system("mv $TMPSTATICFILE $STATICFILE");
system("mv $TMPALIASFILE $ALIASFILE");

release_lock($LOCKFILE);
exit 0;

#
#       Local subroutines
#

sub process_alias {
    my $inalias = shift;
    my ( $theindex, $theentry ) = split( ':', $inalias, 2 );

    $theindex =~ tr/A-Z/a-z/;
    $theentry =~ tr/A-Z/a-z/;

    $ALIASES{"$theindex\0"} = "$theentry\0";
    print ALIASESSRC "$theindex: $theentry\n";
}

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}

sub getAlumni {
	my $cred  = new ICATCredentials('alumni.json')->credentialForName('aliases');
	my $TOKEN = $cred->{'token'};
	$SERVICEURL = $cred->{'url'};

	my $aldata = get("${SERVICEURL}/alumniAliases?token=$TOKEN");
	if ( $aldata =~ /^err / ) {
    		cleanexit($aldata);
	}
	unless ($aldata) {
    		cleanexit("Amaint returned empty aliases file.");
	}

	my ($key,$value);
	foreach $row ( split /\n/, $aldata ) {
		($key,$value) = split(/:/,$row);
		$key =~ s/\@.*//;
		$ALUMNI{$key} = 1;
	}
}

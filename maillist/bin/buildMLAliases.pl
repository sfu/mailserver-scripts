#!/usr/bin/perl -w
#
# buildMLAliases.pl : A program to generate the ml2aliases file and map,
#                     with the maillist-related aliases.
##
# Rob Urquhart
# Changes
# -------
# Use MLRestClient to fetch the maillist aliases information,
# and use ICATCredentials to get the credentials.               2013/05/21 RAU
# Support for Linux: Convert from dbm to DB_File. Change paths	2014/01/16 SH
#
use Getopt::Std;
use Sys::Hostname;
use FindBin;
use lib "$FindBin::Bin/../lib";
#use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;
use Paths;
use MLRestClient;
use DB_File;

$TS           = time;
$ALIASMAPNAME = "$ALIASESDIR/ml2aliases";
$ALIASFILE    = "$ALIASESDIR/ml2aliases";
$TMPALIASFILE = "$ALIASFILE.new.$TS";
$HISTORY      = "$ALIASESDIR/history";
$LOCKFILE     = "/opt/adm/amaintlocks/ml2aliases.lock";
$MAILHOST     = "mailhost.sfu.ca";                       # for pobox and monsoon
$MYHOSTNAME   = hostname();
$MINCOUNT     = 114000;

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

exit(0) if lockInUse($LOCKFILE);
acquire_lock($LOCKFILE);
open( ALIASESSRC, ">$TMPALIASFILE" )
  || cleanexit("Can't open aliases source file: $TMPALIASFILE.\n\n");

# Clean out any existing temporary map.
unlink "$ALIASMAPNAME.tmp$TS";

# Open the temporary maps.
tie( %ALIASES, "DB_File","$ALIASMAPNAME.tmp$TS", O_CREAT|O_RDWR,0644,$DB_HASH )
  || cleanexit("Can't open aliases map $ALIASMAPNAME.tmp$TS.");

# Insert the static '@' entry.
$atsign = "@";
$ALIASES{"$atsign\0"} = "$atsign\0";

$cred = new ICATCredentials('maillist.json')->credentialForName('robert');
my ($client,$aliases);
eval {
    $client = new MLRestClient( $cred->{username}, $cred->{password}, $main::TEST );
    $aliases = $client->getAliasesTxt();
};
print "aliases: $aliases\n" if $main::TEST;
cleanexit("getAliasesTxt returned undef") unless $aliases;
cleanexit($aliases) if ( $aliases =~ /^err / );

my $count = 0;
foreach $line ( split /\n/, $aliases ) {
    ( $alias, $target ) = split /:/, $line;
    if ( $MYHOSTNAME =~ /pobox/) {
        &process_alias( $alias, "$alias\@$MAILHOST" );
    }
    else {
        &process_alias( $alias, $target );
    }
    $count++;
}
close(ALIASESSRC);
untie %ALIASES;

&cleanexit('test run exiting') if $main::TEST;
cleanexit("New ml2aliases file < low water mark: $count") if $count < $MINCOUNT;

# Move the temporary maps and files to their permanent places.
open( JUNK, "cp $TMPALIASFILE $HISTORY|" );
open( JUNK, "mv $TMPALIASFILE $ALIASFILE|" );
open( JUNK, "mv $ALIASMAPNAME.tmp$TS $ALIASMAPNAME.db|" );
release_lock($LOCKFILE);
exit 0;

#
#       Local subroutines
#

sub process_alias {
    my ( $alias, $target ) = @_;

    $alias =~ tr/A-Z/a-z/;
    $target =~ s/^\s+//;
    $target =~ tr/A-Z/a-z/;

    $ALIASES{"$alias\0"} = "$target\0";
    print ALIASESSRC "$alias: $target\n";
}

sub cleanexit {
    my ($msg) = @_;
    release_lock($LOCKFILE);
    unlink "$ALIASMAPNAME.tmp$TS", "$TMPALIASFILE";
    _stderr($msg);
    exit 1;
}


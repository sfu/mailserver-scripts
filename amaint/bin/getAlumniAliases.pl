#! /usr/local/bin/perl
#
# getAlumniAliases.pl: A program to create an aliases map for alumni addresses.
#
# Changes
# -------
#       2009/07/13       First version
#       2013/05/15       Moved to /opt/amaint/prod/bin;   RU
#                        Modified to use ICATCredentials  RU
#

use Getopt::Std;
use LWP::Simple;
use lib '/opt/amaint/prod/lib';
use LOCK;
use ICATCredentials;
use Paths;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

$ALIASMAPNAME = "$ALIASESDIR/alumnialiases";
$ALIASFILE    = "$ALIASESDIR/alumnialiases";
$TMPALIASFILE = "$ALIASFILE.new";
$LOCKFILE     = "$ALIASESDIR/alumnialiases.lock";

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

acquire_lock($LOCKFILE);
my $cred  = new ICATCredentials('alumni.json')->credentialForName('aliases');
my $TOKEN = $cred->{'token'};
$main::SERVICEURL = $cred->{'url'};

my $aldata = get("${main::SERVICEURL}/aliases?token=$TOKEN");
print $aldata if $main::TEST;
if ( $aldata =~ /^err / ) {
    cleanexit($aldata);
}
unless ($aldata) {
    cleanexit("Amaint returned empty aliases file.");
}

open( ALIASESSRC, ">$TMPALIASFILE" )
  || die "Can't open alumnialiases source file: ${TMPALIASFILE}.\n\n";

# Clean out any existing temporary YP map.
unlink "$ALIASMAPNAME.tmp.dir", "$ALIASMAPNAME.tmp.pag";

# Open the temporary maps.
dbmopen( %ALIASES, "$ALIASMAPNAME.tmp", 0644 )
  || die "Can't open aliases map $ALIASMAPNAME.tmp.";

$modtime = sprintf( "%010d", time );
$ALIASES{"YP_LAST_MODIFIED"} = $modtime;
$ALIASES{"YP_MASTER_NAME"}   = $YPMASTER;

# Insert the static '@' entry.

$atsign = "@";
$ALIASES{"$atsign\0"} = "$atsign\0";

# Process the alias-to-username mappings

foreach $row ( split /\n/, $aldata ) {
    &process_alias($row);
}

close(ALIASESSRC);
dbmclose(%ALIASES);

&cleanexit('test run exiting') if $main::TEST;

my ($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,
    $size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($TMPALIASFILE);
cleanexit("$ALIASFILE < low water mark: $size") if $size < 900000;

# Move the temporary maps and files to their permanent places.
open( JUNK, "mv $ALIASMAPNAME.tmp.dir $ALIASMAPNAME.dir|" );
open( JUNK, "mv $ALIASMAPNAME.tmp.pag $ALIASMAPNAME.pag|" );
open( JUNK, "mv $TMPALIASFILE $ALIASFILE|" );

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

    # Strip the domain part out of the alias
    $theindex =~ s/\@.*//;

    $ALIASES{"$theindex\0"} = "$theentry\0";
    print ALIASESSRC "$theindex: $theentry\n";
}

sub cleanexit {
    my $msg = shift;
    print STDERR $msg;
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}

#!/usr/bin/perl
#
# Build aliases for Exchange distribution groups. For now, all DGs will be
# available, but we could change this to exclude restricted-sender
# lists, as deliveries to those are guaranteed to fail from outside Exchange

use DB_File;
use Sys::Hostname;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Utils;
use LOCK;
use Paths;
use ICATCredentials;
use GrouperRestClient;

$EXCHANGESTEM = "resource:app:exchange:groups";
$LOCKFILE = "$LOCKDIR/builddg.lock";
$DGALIASES = "$MAILDIR/dgaliases";
$TS           = time;
$ALIASMAPNAME = "$ALIASESDIR/dgaliases";
$ALIASFILE    = "$ALIASESDIR/dgaliases";
$TMPALIASFILE = "$ALIASFILE.new.$TS";
$MINCOUNT = 0; # Increase this when we get actual DGs

$MAILHOST = "exchange.sfu.ca";
$hostname = hostname();
if ($hostname =~ /pobox/)
{
        $MAILHOST = "mailhost.sfu.ca";
}

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

my $cred = new ICATCredentials('amaint.json') -> credentialForName('grouper_rest');
my $TOKEN = $cred->{'token'};

$client = new GrouperRestClient( $cred->{username}, $cred->{password}, $cred->{grouperUrl} );

# Use this call to restrict groups to only those with a certain attribute, which would allow us to exclude restricted-sender groups
#my $WsGetGroupsResult = $client->getAttributeAssignments([],"group",["etc:attribute:sfu:exchangeRestrictedSender"],"false");
my $res = $client->findGroups({queryFilterType => "FIND_BY_STEM_NAME", stemName => $EXCHANGESTEM});

my $count=0;
if ($res) {
    foreach my $group (@$res) {
        &process_alias( $group->{extension}, $group->{extension} . "\@$MAILHOST" );
        $count++;
    }
}

close(ALIASESSRC);
untie %ALIASES;

&cleanexit('test run exiting') if $main::TEST;
cleanexit("New dgaliases file < low water mark: $count") if $count < $MINCOUNT;

# Move the temporary maps and files to their permanent places.
open( JUNK, "mv $TMPALIASFILE $ALIASFILE|" );
open( JUNK, "mv $ALIASMAPNAME.tmp$TS $ALIASMAPNAME.db|" );
release_lock($LOCKFILE);
exit 0;



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

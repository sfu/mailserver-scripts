#! /usr/bin/perl
#
# getequivs.pl: A program to extract 'equiv' information from Amaint and users'
# zimbra forwards, and use it to build an equiv map and an equiv.byuser map.
# Text files equivalents are also built to aid the admins who have to resolve
# maillist problems.
#
# Run with -t for test mode. This will exit before updating the prod equivs
# file.
#
# Changes
# -------
#
# Use SOAP calls rather than direct db access                2007/10/11 RAU
# Include entries from the zimbra forward file               2008/07/17 RAU
#    (See the getZimbraForwards.pl script also)
# Removed obsolete code. (See the version in ~amaint/etc)    2013/05/22 RAU
#

use Getopt::Std;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Paths;
use Utils;
use LOCK;
use DB_File;

use constant MAXRECORDLENGTH => 1024;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

$DIR             = "$MAILDIR";
$DIR             = "/tmp" if $main::TEST;
$EQUIVNAME       = "$DIR/equivs";
$EQUIVBYUSERNAME = "$DIR/equivs.byuser";
$LOCKFILE        = "$LOCKDIR/equivs.lock";
%equiv           = "";
%equivbyuser     = "";

exit(0) if lockInUse($LOCKFILE);
acquire_lock($LOCKFILE);

# Clean out any existing temporary map.
unlink "$EQUIVNAME.tmp.db";
unlink "$EQUIVBYUSERNAME.tmp.db";

# Open the temporary maps.
tie( %EQUIV,"DB_File", "$EQUIVNAME.tmp.db",O_RDWR|O_CREAT, 0644 )
  || die "Can't open equiv db $EQUIVNAME.tmp.db";
tie( %EQUIVBYUSER,"DB_File", "$EQUIVBYUSERNAME.tmp.db",O_RDWR|O_CREAT, 0644 )
  || die "Can't open equiv.byuser db $EQUIVBYUSERNAME.tmp.";

# Open the text files
open EQUIVTXT,       ">$EQUIVNAME";
open EQUIVBYUSERTXT, ">$EQUIVBYUSERNAME";

# Get the previously generated zimbra forward entries
&process_zimbraforwards;

foreach $key ( keys %equiv ) {
    $EQUIV{"$key\0"} = "$equiv{ $key }\0";
    printf EQUIVTXT "$key $equiv{$key}\n";
}
foreach $key ( keys %equivbyuser ) {
    $EQUIVBYUSER{"$key\0"} = "$equivbyuser{ $key }\0";
    printf EQUIVBYUSERTXT "$key $equivbyuser{$key}\n";
}

untie(%EQUIV);
untie(%EQUIVBYUSER);

&cleanexit if $main::TEST;    # For testing.

# Move the temporary dbs to their permanent places.
open( JUNK, "mv $EQUIVNAME.tmp.db $EQUIVNAME.db|" );
open( JUNK, "mv $EQUIVBYUSERNAME.tmp.db $EQUIVBYUSERNAME.db|" );
chown 155, 155, $EQUIVNAME, "$EQUIVNAME.db";
chown 155, 155, $EQUIVBYUSERNAME, "$EQUIVBYUSERNAME.db";

release_lock($LOCKFILE);
exit 0;

#
#	Local subroutines
#

sub process_equiv {
    local ( $user, $address ) = @_;

    #    local( $fields, $addtogroups, $subfields, $triple, $subgroup, $i );

    $user =~ tr/A-Z/a-z/;
    $address =~ tr/A-Z/a-z/;
    print "process_equiv:user=$user;address=$address\n" if $main::TEST;

    if ( $user && $address ) {
        if (exceedsMaxLength( $user, $address )) {
            _stderr( "Exceeded max record length for user $user" ) if $main::TEST;
            return;
        }
        unless ( contains( $equiv{"$address"}, $user ) ) {
            $equiv{"$address"}    .= "$user:";
            $equivbyuser{"$user"} .= "$address:";
        }
    }
}

sub process_zimbraforwards {
    my $user;
    my $address;

    open ZIMBRA, "/opt/mail/zimbraforwards" or return;
    while (<ZIMBRA>) {
        chomp;
        ( $user, $address ) = split /:/;
        process_equiv( $user, $address );
    }
    close ZIMBRA;
}

sub contains {
    my ( $addrs, $user ) = @_;
    my @addrs = split /:/, $addrs;
    return scalar grep /$user/, @addrs;
}
sub exceedsMaxLength {
    my $user = shift;
    my $address = shift;
    
    my $length = length($user) +1;  # length of the key (user + \0 char)
    # length of record is old record length + separator length
    #                   + length of address + \0 char
    $length += length($equivbyuser{"$user"}) + 1 +
               length($address) + 1;
    return $length > MAXRECORDLENGTH;
}

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    dbmclose(%EQUIV);
    dbmclose(%EQUIVBYUSER);
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    system 'stty', 'echo';
    &cleanexit("Got signal. \n\nAborted");
}

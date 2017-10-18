#!/usr/bin/perl
#
# getExchangeUsers.pl: Fetch list of active accounts from Exchange
#
# Changes
# -------
#       2017/05/12       First version
#

use Getopt::Std;
use Sys::Hostname;
use FindBin;
use lib "$FindBin::Bin/../lib";
use LOCK;
use ICATCredentials;
use IO::Socket::INET;
use Paths;
use JSON;

select(STDOUT);
$|           = 1;               # make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';

$EXCHANGE_PORT = 2016;
$EXUSERSFILE    = "$ALIASESDIR/exchangeusers";
$TMPEXUSERSFILE = "$EXUSERSFILE.new";
$LOCKFILE     = "$ALIASESDIR/exchangeusers.lock";

getopts('t') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

my $hostname = hostname();
if ($hostname =~ /stage/)
{
   $staging=1
}


acquire_lock($LOCKFILE);
my $cred  = new ICATCredentials('exchange.json')->credentialForName('daemon');
my $TOKEN = $cred->{'token'};
$SERVER = $cred->{'server'};
$DOMAIN = $cred->{'domain'};

# In the staging environment, we fetch our users directly from Exchange
# but in prod this won't scale, so use all members of emailpilot-users* lists

if ($staging)
{
	my $ex_users = process_q_cmd_json($SERVER,"$TOKEN getusers");

	print $ex_users if $main::TEST;
	if ( $ex_users =~ /^err / ) {
	    cleanexit($ex_users);
	}
	unless ($ex_users) {
	    cleanexit("Exchange returned empty Users response.");
	}
}
else
{
	$ex_users = [];
	foreach $list ("emailpilot-users","emailpilot-users2")
	{
		if (-f "/opt/mail/maillist2/files/$list/members")
		{
			open(IN1,"/opt/mail/maillist2/files/$list/members") or cleanexit("Can't load members of $list");
			while(<IN1>)
			{
				($user,$junk) = split(/\s+/,$_,2);
				if ($user =~ /\@/)
				{
					next if ($user !~ /\@resource.sfu.ca/);
					$user =~ s/\@resource.sfu.ca//;
				}
				push(@$ex_users,$user);
			}
			close IN1;
		}
	}
}

open( USERSSRC, ">$TMPEXUSERSFILE" )
  || die "Can't open Exchange Users tmp file: ${TMPEXUSERSFILE}.\n\n";

# Process each Exchange user

foreach $row ( @$ex_users ) {
    # Just in case, skip any usernames with spaces in the account name
    next if ($staging && $row->{'SamAccountName'} =~ / /);
    # print the user's account name @ exchange domain
    if ($staging)
    {
    	print USERSSRC $row->{'SamAccountName'},": ",$row->{'SamAccountName'},"\@$DOMAIN\n";
    }
    else
    {
    	print USERSSRC "$row: $row\@exchange.sfu.ca\n";
    }
}

close(USERSSRC);

&cleanexit('test run exiting') if $main::TEST;

my ($dev,$inode,$mode,$nlink,$uid,$gid,$rdev,
    $size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($TMPEXUSERSFILE);
cleanexit("$TMPEXUSERSFILE < low water mark: $size") if $size < 150;

# Move the temporary maps and files to their permanent places.
open( JUNK, "mv $TMPEXUSERSFILE $EXUSERSFILE|" );

release_lock($LOCKFILE);
exit 0;

#
#       Local subroutines
#

sub cleanexit {
    my $msg = shift;
    _stderr($msg);
    release_lock($LOCKFILE);
    exit 1;
}

sub EXITHANDLER {
    &cleanexit("Aborted");
}

sub _stderr($) {
    my ($line) = @_;

    print STDERR scalar localtime() . " $line\n";
}

# Decode result from JSON before passing back
sub process_q_cmd_json()
{
	my ($server,$cmd) = @_;
	my $res = process_q_cmd($server,$cmd);
	my $jsonobj = JSON->new->allow_nonref;

	$g_res = $res;
	if ($res =~ /^err/)
	{
		$res =~ s/^err//;
		$cmd_err = $res;
		return undef;
	}
	eval {
		$jsonref = $jsonobj->decode($res);
	};
	if ($@) {
		return undef;
	}
	return $jsonref;
}
	

sub process_q_cmd()
{
	my ($server,$cmd) = @_;
	my $sock = IO::Socket::INET->new("$server:$EXCHANGE_PORT");
	if ($sock)
	{
		$junk = <$sock>;	# wait for "ok" prompt
		print $sock "$cmd\n";
		@res = <$sock>;
		close $sock;
	}
	else
	{
		@res = ["err Connection error: $@"];
	}

	return join("",@res);

}


#! /usr/local/bin/perl
#
# getzimbraaliases.pl: A program to extract 'aliases' file information from the
# zimbra server, and and use it to build an alias map and a backup text file.
#
# Changes
# -------
#	June 1 2008: Derived from getaliases, but pulls accounts from Zimbra
#	Apr 25 2009: Modified to no longer send mail to accounts that are
#		added, or a summary of all accounts added, as migration is
#		now complete. Process should now be run hourly to ensure
#		rm-rstar aliases are in sync with Zimbra accounts
#   Use Amaintr.pm module. Moved to ~/prod/bin              2013/05/15 RU

use Getopt::Std;
use SOAP::Lite;
use lib '/opt/amaint/prod/lib';
use ICATCredentials;

@nul = ('not null','null');
select(STDOUT); $| = 1;		# make unbuffered
$SIG{'INT'}  = 'EXITHANDLER';
$SIG{'HUP'}  = 'EXITHANDLER';
$SIG{'QUIT'} = 'EXITHANDLER';
$SIG{'PIPE'} = 'EXITHANDLER';
$SIG{'ALRM'} = 'EXITHANDLER';


$YPDOMAIN = "sfu.ca";
$YPDIR = "/opt/mail";
$ALIASMAPNAME = "$YPDIR/zimbraaliases";
$ALIASFILE = "$YPDIR/zimbraaliases";
$TMPALIASFILE = "$ALIASFILE.new";
$LOCKFILE = "/opt/adm/amaintlocks/zimbraaliases.lock";	# 97/03/20 RAU
$BOUNCEPROG = "bounceprog";
$ALIASCMD = "/usr/bin/ssh -l zimbra mailbox1.nfs.sfu.ca /opt/sfu/getaccts";
$ZMDOMAIN = "connect.sfu.ca";
@SANITYCHK = ("hillman","keithf","admin");	# If any of these accounts aren't found in zmprov output, bail
$EXCLUDES = "wiki|admin|spam.ui5gzd9xy|ham.uzqsnwwk|test1|majordom|maillist|alumhelp"  ;	# Accounts that shouldn't be put into aliases map
$LOGFILE = "/opt/amaint/zimbra-adds.log";
$TOOLKITLOG = "toolkit\@cluculz.sfu.ca:/home/toolkit/newemail_data/enrollment/zimbra-adds.log";

my $cred = new ICATCredentials('zimbra.json') -> credentialForName('zaliases');
my $SVCTOKEN = $cred->{'token'};
my $SERVICE_URL = $cred->{'url'};


getopts('ta') or die("Bad options");
$main::TEST = $opt_t ? $opt_t : 0;

$usertodo = $ARGV[0];

$byadmin = (!$opt_a && defined($ARGV[1])) ? "by " . $ARGV[1] : "";

$quiet = ($byadmin eq "by -q") ? 1 : 0;

if ((!defined($usertodo) && !$opt_a) || $usertodo =~ /^-/)
{
	print "Usage: getzimbraaliases {-a | userid}\n";
	exit 1;
}


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
	if (!$opt_a && $f eq $usertodo)
	{
		$foundme = 1;
		last;
	}
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


$aliasfile = $opt_a ? ">$TMPALIASFILE" : ">>$ALIASFILE";

open( ALIASESSRC, "$aliasfile" ) || die "Can't open aliases source file: $aliasfile.\n\n";

# Clean out any existing temporary YP map.
unlink "$ALIASMAPNAME.tmp.dir","$ALIASMAPNAME.tmp.pag";

# Open the existing map
dbmopen(%ALIASESOLD,"$ALIASMAPNAME",0644) || die "Can't open aliases map $ALIASMAPNAME.";
# Open the temporary maps.
if ($opt_a)
{
	dbmopen(%ALIASES,"$ALIASMAPNAME.tmp",0644) || die "Can't open aliases map $ALIASMAPNAME.tmp.";
	$modtime=sprintf("%010d", time);
	$ALIASES{"YP_LAST_MODIFIED"} = $modtime;
	$ALIASES{"YP_MASTER_NAME"} = $YPMASTER;

	# Insert the static '@' entry.
	$atsign="@";
	$ALIASES{ "$atsign\0" } = "$atsign\0";
}


if (!$opt_a && !$foundme)
{
	print "NO: $usertodo not found in Zimbra. Adding user to aliases would result in lost mail. Aliases unchanged.\n";
	close( ALIASESSRC );
	dbmclose( ALIASESOLD );
	&cleanexit;
}

if ($opt_a && $found < scalar(@SANITYCHK))
{
    print "NO: One or more mandatory accounts not found in zimbra aliases. Not updating Aliases."; 
    close( ALIASESSRC );
    dbmclose( ALIASESOLD );
    &cleanexit;
}

# Process the aliases

if ($opt_a)
{
	foreach $za (@zmaliases) {
		next if ($za !~ /\@sfu.ca$/);		# For now at least, skip anything other than @sfu.ca users
		$za =~ s/@.*$//;		# Strip domain part
		next if ($za =~ /^($EXCLUDES)$/);
		&process_alias($za);
	}
}
else
{
    $theindex = $usertodo;
    $theindex =~ tr/A-Z/a-z/;
    $theentry = "$theindex\@$ZMDOMAIN";

    if (!defined($ALIASESOLD{ "$theindex\0" } ))
    {
	push (@newusers, $theindex);

# Apr 25/09: All users now in Zimbra. no need to send mail for newly added users
#	if (!$quiet)
#	{
#	    send_mail_before();
#	    sleep 3;
#	}
    	$ALIASESOLD{ "$theindex\0" } = "$theentry\0";
    	print ALIASESSRC "$theindex: $theentry\n";
#	if ($quiet)
#	{
#		#don't send mail, but still gotta update logfile
#		open(LOG,">>$LOGFILE");
#		printf LOG "%10s %d\n",$usertodo,time();
#		close LOG;
#	}
#	else
#	{
#		send_mail_after();
#	}
    }
}


close( ALIASESSRC );
dbmclose( ALIASES ) if ($opt_a);
dbmclose( ALIASESOLD );

&cleanexit if $main::TEST;	# For testing.


if (!$opt_a)
{
	unlink("$LOCKFILE.$$" );
	unlink($LOCKFILE);
	exit 0;
}
	

#send_mail_before() if (defined(@newusers));

# Move the temporary maps and files to their permanent places.
open(JUNK, "mv $ALIASMAPNAME.tmp.dir $ALIASMAPNAME.dir|" );
open(JUNK, "mv $ALIASMAPNAME.tmp.pag $ALIASMAPNAME.pag|" );
open(JUNK, "mv $TMPALIASFILE $ALIASFILE|" );

#sleep 10;
#send_mail_after() if (defined(@newusers));

#if ($opt_a)
#{
#	# All users, so copy log file to Cluculz
#	`/usr/bin/scp $LOGFILE $TOOLKITLOG`;
#}

unlink("$LOCKFILE.$$" );
unlink($LOCKFILE);
exit 0;

#
#	Local subroutines
#

sub process_alias {
    local( $theindex ) = @_;
    local( $fields, $addtogroups, $subfields, $triple, $subgroup, $i );
    
    
    $theindex =~ tr/A-Z/a-z/;
    $theentry = "$theindex\@$ZMDOMAIN";

    push (@newusers,$theindex) if (!defined($ALIASESOLD{ "$theindex\0" } ));
    
    $ALIASES{ "$theindex\0" } = "$theentry\0";
    print ALIASESSRC "$theindex: $theentry\n";
    
#    if ( $theentry =~ /@/ )  # ...then it needs a 'byaddr' reverse entry.
#    {
#	$theentry =~ s/ //g;
#	$ALIASESBYADDR{ $theentry } = $theindex;
#    }
}


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

sub send_mail_before()
{
   foreach $user (@newusers)
   {
       open(MAIL,"|/usr/lib/sendmail -f zimbra\@sfu.ca $user\@sfu.ca") or die "Couldn't invoke Sendmail. Aliases not processed\n";
	print MAIL <<EOM;
From: postmaster\@sfu.ca
To: "SFUConnect User" <$user\@sfu.ca>
Subject: Access your email now at http://connect.sfu.ca

Hello,

This is to inform you that your SFU Connect account is about to be created. Your Inbox will be migrated over to the new system over the next 24 hours. If you use SFUwebmail, your email folders and address book entries will also be copied over during the next 48 hours. For more details, please see below.

Please keep in mind that this is the last email that will be delivered to you via the old email system, and it is the last message that you will receive in SFUwebmail.  From now on, all email sent to $user\@sfu.ca will come to your SFU Connect account. SFUwebmail will show only messages sent and received before you switched to SFU Connect, and should be treated as a read-only archive. SFUwebmail will be retired at some point in the future.

Going forward, you can access your SFU email in the following ways:

   - WEB: Using your browser (for example, Inernet Explorer), go to http://connect.sfu.ca and bookmark this as your new email link. 
   
   - POP: No change in settings is required for POP clients (for example, Eudora). Depending on the POP client settings, some people may receive double copies of messages in the Inbox of the POP client (one-time only). If this happens, please delete the duplicates. If you cannot connect, please check that your incoming server is set to pop.sfu.ca or popserver.sfu.ca.

   - IMAP: The next time you open your IMAP client (for example, Thunderbird), it will automatically find your Inbox on the new system. If you cannot connect, please check that your incoming server is set to imap.sfu.ca or imapserver.sfu.ca.  To access your old folders, you can add a new profile with the setting oldimap.sfu.ca and drag & drop these folders into your main profile. We recommend you contact the computer technical support in your department if you require assistance with this step.

You can find an FAQ about how the transition affects you, and instructions for seting up a signature, filters, and vacation messages in the new system at http://www.sfu.ca/newemail/transition. 

For more information about SFU Connect, please visit http://www.sfu.ca/newemail. If you require help with SFU Connect and you are a student, please visit http://www.sfu.ca/techhelp. Staff and faculty, please contact your department's computer support technician. 

Cheers!
The SFU Connect Team

EOM
	close MAIL;
    }
    sleep 10;
}


sub send_mail_after()
{
   foreach $user (@newusers)
   {
       	if (!open(MAIL,"|/usr/lib/sendmail -f zimbra\@sfu.ca $user\@sfu.ca"))
	{ 
	    print "Couldn't invoke Sendmail for $user but alias has been added\n"; 
	    next; 
	}
	print MAIL <<EOM;
From: postmaster\@sfu.ca
To: "SFU Connect User" <$user\@sfu.ca>
Subject: Welcome to SFU Connect

Hi there,

Welcome to SFU Connect.  Your Inbox will be migrated over to the new system over the next 24 hours. If you use SFUwebmail, your email folders and address book entries will also be copied over during the next 48 hours. For more details, please see below.

From now on, all email sent to *****@sfu.ca will come to your SFU Connect account. SFUwebmail will show only messages sent and received before you switched to SFU Connect, and should be treated as a read-only archive. SFUwebmail will be retired at some point in the future. 

From now on, access to your email is available in the following ways: 

    *Web: SFUwebmail has been replaced by a new email web interface, SFU Connect, which is accessed via http://connect.sfu.ca. It can be used by everyone and offers many features over and beyond the old SFUwebmail. Using your browser (for example, Inernet Explorer), go to http://connect.sfu.ca and bookmark this as your new email link.

 - If you used SFUwebmail, your data (emails, address book) will automatically be moved over to the new system.
 - Any filters you had in SFUwebmail will need to be set-up again in the new system via http://connect.sfu.ca. 
 - For information on SFUwebmail data transfer, setting up filters, vacation messages and/or forwarding, please see: http://www.sfu.ca/newemail/faq.

The SFU Connect web interface is a collaborative suite of tools, including Email, Calendar, Address Book, and Briefcase. It offers many unique features that were not previously available in SFUwebmai, such as sharing folders. To learn more about SFU Connect and its functionality, please visit http://www.sfu.ca/newemail. There you will find user guides, animated online tutorials, and other resources. 

- Desktop email program (Eudora, Thunderbird, Apple Mail, Mutt, Outlook, etc.) You may choose to continue using the email program most familiar to you. For questions related to desktop email programs, please contact your department's computer support person. 
Any forwarding and/or vacation messages you had will need to be set up again in the new system.
Any filters you have in Apple Mail, Thunderbird, etc will still work.
You can find an FAQ about how the transition affects you, and instructions for seting up a signature, filters, and vacation messages in the new system at http://www.sfu.ca/newemail/transition.

  - POP : No change in settings is required for POP clients (for example, Eudora). Depending on the POP client settings, some people may receive double copies of messages in the Inbox of the POP client (one-time only). If this happens, please delete the duplicates. If you cannot connect, please check that your incoming server is set to pop.sfu.ca or popserver.sfu.ca.

  - IMAP : The next time you open your IMAP client (for example, Thunderbird), it will automatically find your Inbox on the new system. If you cannot connect, please check that your incoming server is set to imap.sfu.ca or imapserver.sfu.ca.

   - To access your old IMAP folders, you can add a new profile with the setting oldimap.sfu.ca and drag & drop these folders into your main profile. We recommend you contact the computer technical support in your department if you require assistance with this step. 


Besides the many new features available in SFU Connect, there are a few important differences to note:

  - Although your Quota is much larger, it is now a "hard" quota. If you exceed it, you will no longer be able to send or receive mail until you reduce your usage below quota. You will start getting daily warnings of this if you exceed 90% quota.

  - The web Trash folder behaves differently than in SFUwebmail. It now has a 1-year lifetime for messages put into the Trash, which is calculated from the time when the item was *received*, not from when it was placed in the Trash. If you place a 2-year old message in the Trash, it will be removed from the Trash shortly afterwards. If you want to remove messages from the Trash before they are one year old, simply empty the Trash folder periodically (right-click on the Trash folder and choose "Empty Trash").

Please note: In order to allow you to plan ahead for any necessary system outages, there is a scheduled maintenance window for SFU Connect on the first Saturday of every month from 10pm to 2am.

For more information about SFU Connect, please visit http://www.sfu.ca/newemail. If you require help with SFU Connect and you are a student, please visit http://www.sfu.ca/techhelp. Staff and faculty, please contact your department's computer support technician. 

Cheers!
The SFU Connect Team

EOM
	close MAIL;
    }

    # Open connection to SOAPServer to get role/dept info for added accounts
    my $service = SOAP::Lite -> service( $SERVICE_URL );

    open(LOG,">>$LOGFILE");

    my $count = scalar(@newusers);
    open(MAIL,"|/usr/lib/sendmail emailpilot-tech\@sfu.ca,bahram\@sfu.ca");
#    open(MAIL,"|/usr/lib/sendmail hillman\@sfu.ca,keithf\@sfu.ca");
    print MAIL <<EOMM;
From: postmaster\@sfu.ca
To: emailpilot-tech\@sfu.ca
Subject: Added $count users to Zimbra $byadmin

The following users were added to Zimbra:

EOMM
    foreach $user (@newusers)
    {
	next if ($user =~ /^icat\d\d$/);
	eval {
	    $info = $service->infoForComputingID($user, $SVCTOKEN);
	};
	@role = ();
	$dept = "";
	if (defined($info))
	{
	    $role = $info -> {'type'};
	    push (@role, $_) foreach (@$role);  # so @role contains array of roles
        
	    $dept = $info -> {'department'};
	}
	printf MAIL "%10s %30s  %s\n",$user,join(",",sort(@role)),$dept;
	printf LOG "%10s %d %30s  %s\n",$user,time(),join(",",sort(@role)),$dept;
    }
    close MAIL;
    close LOG;

}

#!/usr/bin/perl

use Net::SMTP;


$logfile = "/home/hillman/mail/log/process_mig_msg.log";
$migdir = "/home/hillman/mail/migrations";
$doneemailfile = "/home/hillman/sec_html/mail/donemsg";

open(LOG,">>$logfile");

$found = 0;

while(<>)
{
	$msg .= $_;
	if (!$found && /Subject: CM365: User ([\w\d]+) (started|completed) for ([\w, ]+)/)
	{
		$mailbox = $1;
		$status = $2;
		$what = $3;
		$found = 1;
	}
}


if ($found)
{
	print LOG "Processing migration results for $mailbox\n";
	$outdir = "$migdir/$mailbox";
	$activedir = "$migdir/active";
	if (! -d $outdir)
	{
		mkdir $outdir or die "Can't mkdir $outdirbase";
	}

	if (! -d $activedir)
	{
		mkdir $activedir or die "Can't mkdir $activedir";
	}
	
	if    ($what =~ /Calendar/) { $file = "calendar";}
	elsif ($what =~ /Recent/) { $file = "recent";}
	elsif ($what =~ /All /) { $file = "all";}
	else { die "Unrecognized migration: $what";}

	open(OUT,">$outdir/$file") or die "Can't open $outdir/$file for writing\n";
	print OUT "$status\n";
	close OUT;		
	if ($status eq "started")
	{
		`touch $activedir/$mailbox.$file`;
	}
	else
	{
		unlink "$activedir/$mailbox.$file" if (-e "$activedir/$mailbox.$file");
	}

	if ($file eq "all" && $status eq "completed")
	{
		# Send email to end-user that they're all done
		send_message("localhost", $doneemailfile, $mailbox);
	}
}
else
{
	print LOG "Can't identify mailbox for $msg";
}

close LOG;
exit 0;

sub send_message()
{
    my ($server,$msgfile,$recipient) = @_;
    my $msg;


    open(IN,$msgfile) or return undef;
    while(<IN>)
    {
        s/%%user/$user/g;
        $msg .= $_;
    }
    close IN;

    my $smtp = Net::SMTP->new($server);
    return undef unless $smtp;
    my $rc = $smtp->mail('amaint@sfu.ca');
    if ($rc)
    {
        $rc = $smtp->to("$recipient\@sfu.ca");
        if ($rc)
        {
            $rc = $smtp->data([$msg]);
        }
        $smtp->quit();
    }
    return $rc;
}

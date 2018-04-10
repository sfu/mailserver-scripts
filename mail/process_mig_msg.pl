#!/usr/bin/perl

use Net::SMTP;
use MIME::Parser;
use DB_File;
use File::Copy;

sub _log;


$tmpdir = "/tmp/$$";
$logfile = "/home/hillman/mail/log/process_mig_msg.log";
$migdir = "/home/hillman/mail/migrations";
$doneemailfile = "/home/hillman/sec_html/mail/donemsg";

open(LOG,">>$logfile");
mkdir($tmpdir);

$found = 0;

$parser = new MIME::Parser;
$parser->output_under($tmpdir);


$entity = $parser->parse(\*STDIN) or die "MIME Parser Unable to parse message"; 

$header = $entity->head();
$subj = $header->get('Subject');


if ($subj =~ /CM365: User ([\w\d]+) (started|completed) for ([\w, ]+)/)
{
	$mailbox = $1;
	$status = $2;
	$what = $3;
	$found = 1;
}
elsif ($subj =~ /CM365: Users Completed/)
{
	$found = 2;
	$status = "completed";
}
else
{
	_log "Skipping msg. Unrecognized subject: $subj\n";
}



if ($found == 1)
{
	_log "Processing migration results for $mailbox\n";
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
elsif ($found == 2)
{
	# Handle the 'User completed' msgs that CM365 generates. These are more complex
	# MIME message with Zip attachments. 
	# We need to step through the message and parse each user block

	@parts = $entity->parts();
	if (!scalar(@parts))
	{
		_log "CM365 message had no MIME parts. Couldn't process\n";
	}
	else
	{
		# First part is a multipart/alternative, so we're making the (gross?)
		# assumption that part0 of the multipart will be the text part
		$text = $parts[0]->parts(0)->bodyhandle()->as_string();

		# Zip file is the second part
		$zipfile = $parts[1]->bodyhandle();

		$inuser = 0;
		$migname = "All";
		foreach $l (split(/\n/,$text))
		{
			if ($l =~ /Users Completed report for [\d:\/ APM]+ , (.*)/)
			{
				$migname = $1;
				# just in case there's colons
				$migname =~ s/://g;
			}
			elsif ($l =~ /\*   User Statistics Summary '([a-z0-9]+)'/)
			{
				$mailbox = $1;
				$inuser = 1;
				read_user();
				next;
			}
			if ($inuser && $l !~ /\*   /)
			{
				write_user();
				$inuser = 0;
				next;
			}
			if ($inuser)
			{
				if ($l =~ /\*   (Status|Slave machine|Total export failure|Total import failure|Total export success|Total import success):(.*)/)
				{
					$user{"$migname.$1"} = $2;
				}
			}
		}
		write_user if ($inuser);

		# Attempt to unpack the zip file
		if (defined($zipfile->path))
		{
			$zf = $zipfile->path();
			system("cd $tmpdir; unzip \"$zf\"");
			opendir(DIR,$tmpdir);
			@reportfiles = grep { /\.html/ } readdir DIR;
			closedir DIR;
			foreach $file (@reportfiles)
			{
				if ($file =~ /UserMigrationReport-([a-z0-9]+)/)
				{
					$mailbox = $1;
					mkdir ("$migdir/$mailbox/reports") if (! -d "$migdir/$mailbox/reports");
					move("$tmpdir/$file","$migdir/$mailbox/reports");
				}
			}
			_log "Unpacked ", scalar(@reportfiles), " reports from attached Zipfile $zf\n";
		}
	}
}

close LOG;

system("rm -rf $tmpdir");

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

sub write_user()
{
	mkdir ("$migdir/$mailbox") if (! -d "$migdir/$mailbox");
	open(OUT,">$migdir/$mailbox/userstats.txt");
	foreach $k (keys %user)
	{
		print OUT "$k:",$user{$k},"\n";
	}
	close OUT;
}

sub read_user()
{
	mkdir ("$migdir/$mailbox") if (! -d "$migdir/$mailbox");
	%user = ();
	if (-f "$migdir/$mailbox/userstats.txt")
	{
		open(UIN,"$migdir/$mailbox/userstats.txt");
		while(<UIN>)
		{
			($k,$v) = split(/:/,$_,2);
			$user{$k} = $v;
		}
		close UIN;
	}
}

sub _log()
{
    $msg = shift;
    print LOG scalar localtime(),": ",$msg;
}

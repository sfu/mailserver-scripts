#!/usr/bin/perl
#
# Create the survey db used by 'rewritemail' to "unanonymize" survey
# emails. 
#
# Usage: survey-createdb.pl surveyname < survey_sourcefile.txt
#
# Source file is in the format:
# SFUID		userid		token		final anonymous email addr
#0123456786	dbigueta	77058840	nsse_survey+77058840@sfu.ca
#
# Alternatively, if you don't have a source file in this format, you likely
# just have a list of student numbers. Specify the '-a' flag to 
# generate both the anonymous email addresses (saved to a file) and the
# survey DB
#
use Getopt::Std;
use DB_File;
use FindBin;
use lib "$FindBin::Bin/../lib";
use Amaintr;
use Utils;
use LOCK;
use ICATCredentials;

sub usage
{
	print "Usage: survey-createdb.pl [-a] -s surveyname < source_file\n";
	print "    -s surveyname  Name of the survey - E.g. nsse. Mandatory\n";
	print "    -a             Anonymize source data. Use this option if you only have\n";
	print "                   the list of EMPLIDs and need to generate the anonymized email addresses as well\n\n";
	exit 1;
}
getopts("as:") or usage();

my $SurveyDBPath = "/opt/mail/surveys";
my $survey = $opt_s;
my $cred  = new ICATCredentials('amaint.json')->credentialForName('amaint');
my $TOKEN = $cred->{'token'};

my $amaintr = new Amaintr( $TOKEN, $main::TEST );

usage() if (!$survey);

if ($opt_a)
{
	if (-e "$SurveyDBPath/${survey}_source.csv")
	{
		print "$SurveyDBPath/${survey}_source.csv Already exists! Will not overwrite\n\n";
		exit 1;
	}
	open(ANON,">$SurveyDBPath/${survey}_source.csv") or die "Can't open $SurveyDBPath/${survey}_source.csv for writing\n";
	print ANON "SFUID,userid,token,email\n";
}

if (-e "$SurveyDBPath/${survey}_survey.db")
{
	print "$SurveyDBPath/${survey}_survey.db already exists! Please remove or rename before running this script\n\n";
	exit 1;
}
tie %aliases,"DB_File","$SurveyDBPath/${survey}_survey.db",O_RDWR|O_CREAT,0666,$DB_HASH ;

my ($sfuid, $account, $mailalias, $nsseaddress);
while ( <STDIN> ) {
	if ($opt_a)
	{
		chomp;
		if (! /^\d+$/)
		{
			print STDERR "Skipping line. Not an SFUID: $_\n";
			next;
		}
		$person = $amaintr->getPerson("sfuid",$_);
		$sfuid = $_;
		if (scalar(@$person) > 1)
		{
			print STDERR "WARNING: More than one person object returned for $_. Can't process!\n";
			next;
		}
		$account = ${$person}[0]->{username};
		# Generate a random 8 digit number
		$mailalias = int(rand(90000000)) + 10000000;
		$nsseaddress = "${survey}_survey+$mailalias\@sfu.ca";
		print ANON "$sfuid,$account,$mailalias,$nsseaddress\r\n"; 
	}
	else
	{
		($sfuid, $account, $mailalias, $nsseaddress) = split /\s+/, $_ ;
		chomp ( $nsseaddress ) ;
	}
	$aliases{$mailalias} = $account . '@sfu.ca' ;
}

close ANON if ($opt_a);

untie %aliases ;

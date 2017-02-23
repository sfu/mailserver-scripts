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
# (note, mostly historical - technically only the userid and token are used)

my $SurveyDBPath = "/opt/mail/surveys";
use DB_File ;

my $survey = $ARGV[1];

if (!$survey)
{
	print "Usage: survey-createdb.pl surveyname < survey_sourcefile.txt\n";
	exit 1;
}

tie %aliases,DB_Hash,"$SurveyDBPath/${survey}_survey.db",O_RDWR|O_CREAT,0666 ;

while ( <> ) {
	my ($sfuid, $account, $mailalias, $nsseaddress) = split /\t/, $_ ;
	chomp ( $nsseaddress ) ;
	$aliases{$mailalias} = $account . '@sfu.ca' ;
}


untie %aliases ;



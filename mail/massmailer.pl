#!/usr/bin/perl
#
# Simple script to mass-mail a list of users using a template as the message source
# List of users can either be specified as a maillist or as a CSV file
# If using a maillist, only the user's username can be merged into the template
# If using a CSV file, all fields in the CSV will be searched for a corresponding variable
# in the template file and the corresponding value for each user substituted into the template
# Variables are specified in the Template file using the format "%%variable%%" - e.g:
#  To: %%user%% 

use Getopt::Std;
use Text::CSV::Hashify;
use Net::SMTP;
# Find our lib directory
use lib "/opt/amaint/lib";
use ICATCredentials;
# Find the maillist lib directory
use lib "/opt/amaint/maillist/lib";
use MLRestClient;

sub HELP_MESSAGE()
{
	usage();
}

sub usage()
{
	print "Send mass mail to a group of users, customizing a template to each recipient.\n";
	print "Usage: massmailer.pl ( -c users.csv | -m maillist ) -t templatefile\n";
	print "    -c file.csv       Specify a CSV file containing a list of names and optionally other columns to be merged into template\n";
	print "    -m maillist       Specify a maillsit of users to email. -c and -m options are mutually exclusive and one or the other must be given\n";
	print "                      If a maillist is specified, only the username or email address can be merged into the template\n";
	print "    -t templatefile   Specify the template file to merge with. This option is mandatory\n";
	print "    -f from\@domain    Email address to use in the From field. If not specified, the one in the Template file is used.\n";
	exit 1;
}

getopts('c:df:m:t:') or usage();

usage() if ((!$opt_c && !$opt_m) || !$opt_t || ($opt_c && $opt_m));
if(! -f $opt_t) 
{
	print "File not found: $opt_t\n";
	usage();
}
if ($opt_c && (! -f $opt_c))
{
	print "File not found: $opt_c\n";
	usage();
}

if ($opt_m)
{
	$userlist = members_of_maillist($opt_m);
	if (!scalar(@{$userlist}))
	{
		print "Maillist $opt_m is empty or doesn't exist. Nothing to do.\n";
		exit 1;
	}
}
elsif ($opt_c)
{
	$csvobj = Text::CSV::Hashify->new( {
        file        => $opt_c,
        format      => 'aoh', # array of hashes, as we don't know what the primary key is
    } );

    $userlist = $csvobj->all; # Returns a ref to an array of hashes, one hash per CSV row
    # Determine the right column for the username
    $u = ${$userlist}[0];
    if (defined($u->{username}))
	{
		$usercol = "username";
	}
	elsif (defined($u->{email}))
	{
		$usercol = "email";
	}
	elsif (defined($u->{user}))
	{
		$usercol = "user";
	}
	else
	{
		print "Unable to find a \"username\",\"email\", or \"user\" column in the CSV file. Can't continue";
		exit 1;
	}
}

if ($opt_f && $opt_f !~ /\@/)
{
	print "From-Address must be a valid email address. $opt_f is not.\n"
}


# Parse the template file. All but a select few headers are ditched
open(TMPL,"$opt_t") or die "Can't open $opt_t for reading";
$inheader=1;
if ($opt_f)
{
	$template = "From: $opt_f\n";
}
else
{
	$template = "";
}

while(<TMPL>)
{
	if (!$inheader)
	{
		$template .= $_;
		next;
	}
	if (/^$/)
	{
		$template .= $_;
		$inheader = 0;
		next;
	}
	if (/^[\s]+/)
	{
		# Continuation of previous header line. If last line was skipped, skip this one too
		next if ($skipped);
		$template .= $_;
		next;
	}
	if (/^To: /)
	{
		$template .= "To: %%email%%\n";
		$skipped = 0;
		next;
	}
	if (/^(Subject|Content-Type|MIME-Version): /) # Add any other headers we wish to preserve here
	{
		$template .= $_;
		$skipped = 0;
		next;
	}
	if (/^From: /)
	{
		if ($opt_f)
		{
			$skipped = 1;
			next;
		}
		$template .= $_;
		$skipped = 0;
		next;
	}
	$skipped = 1;
}
close TMPL;

print "Template: $template" if ($opt_d);

# Main delivery loop

foreach $u (@{$userlist})
{
	if ($opt_m)
	{
		$user = $u;
	}
	else # $opt_c
	{
		$user = $u->{$usercol};
	}
	if ($user !~ /\@/)
	{
		$user .= "\@sfu.ca";
	}
	$unscopeduser = $user;
	$unscopeduser =~ s/\@.*//;

	my $msg = $template;
	$msg =~ s/%%email%%/$user/g;
	if ($opt_m)
	{
		$msg =~ s/%%user%%/$unscopeduser/g;
	}
	else
	{
		foreach $k (keys %{$u})
		{
			next if ($k eq 'username' || $k eq 'email' || $k eq 'user');
			$val = $u->{$k};
			$msg =~ s/%%$k%%/$val/g;
		}
	}

	if ($opt_d)
	{
		print "Message for $user:\n$msg";
	}
	else
	{
		send_message("localhost",$msg,$user);
	}
}

exit 0;

sub send_message()
{
    my ($server,$msg,$recipient) = @_;

    my $smtp = Net::SMTP->new($server);
    return undef unless $smtp;
    my $rc = $smtp->mail('amaint@sfu.ca');
    if ($rc)
    {
        $rc = $smtp->to($recipient);
        if ($rc)
        {
            $rc = $smtp->data([$msg]);
        }
        $smtp->quit();
    }
    return $rc;
}

sub restClient {
    if (!defined $restClient) {
       my $cred = new ICATCredentials('maillist.json')->credentialForName('robert');
       $restClient = new MLRestClient($cred->{username}, 
                                      $cred->{password},$main::TEST);
    }
    return $restClient;
}

sub members_of_maillist()
{
    my $listname = shift;
    my $memarray = [];
    eval {
        my $client = restClient();
        my $ml = $client->getMaillistByName($listname);
        if (defined($ml))
        {
            my @members = $ml->members();
            return undef unless @members;
            if ($ml->memberCount() != scalar @members) 
            {
                print "ERROR: Member count returned from MLRest doesn't match maillist member count. Aborting";
                return undef;
            }
            foreach my $member (@members) 
            {
                next unless defined $member;
                if ($member->type eq "2")
                {
                	# Nested list
                	my $nestedmembers = members_of_maillist($member->canonicalAddress());
                	if ($nestedmembers)
                	{
                		push @{$memarray}, @{$nestedmembers};
                	}
                }
                else
                {
                	push @{$memarray}, $member->canonicalAddress();
            	}
            }
        }
    };
    if ($@) {
        print "ERROR: Caught error from MLRest client. Aborting";
        return undef;
    }
    return $memarray;
}
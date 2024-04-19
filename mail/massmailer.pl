#!/usr/bin/perl
#
# Simple script to mass-mail a list of users using a template as the message source
# List of users can either be specified as a maillist or as a CSV file
# If using a maillist, only the user's username can be merged into the template
# If using a CSV file, all fields in the CSV will be searched for a corresponding variable
# in the template file and the corresponding value for each user substituted into the template
# Variables are specified in the Template file using the format "%%variable%%" - e.g:
#  To: %%user%%
#
# Revisions:
#  2021/02/12 - Added special column name "bulletlist": the column value will be split on ',' and turned into a bulleted list
#                The message template should contain "%%bulletlits%%" where the text will go and %%bulletlisthtml%% where the
#                html will go
#  2021/02/15 - Added special column 'jsonlist': The column value will be converted from JSON to a data structure which is
#                expected to be a potentially nested list of bullets. Hash keys become bullet points and hash values become
#                indented bulleted lists under the bullet point 

use Getopt::Std;
use Text::CSV::Hashify;
use Net::SMTP;
use Time::HiRes;
use DB_File;
use JSON;
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
	print "    -m maillist[,maillist,-maillist]\n";       
	print "						 Specify one or more maillists of users to email. Use [-list] to exclude members of that list. \n";
	print "						 -c and -m options are mutually exclusive and one or the other must be given\n";
	print "                      If a maillist is specified, only the username or email address can be merged into the template\n";
	print "    -t templatefile   Specify the template file to merge with. This option is mandatory\n";
	print "    -f from\@domain   Email address to use in the From field. If not specified, the one in the Template file is used.\n";
	print "    -r 				 Preserve the Reply-To header from the template file (default is to ignore it)\n";
	print "    -b                Enable bounce tracking. Envelope From will be set to sfu_bounces+UUID\@sfu.ca. /usr/local/mail/bouncetracker.db\n";
	print "                      Will contain a map of UUID to recipient\n";
	exit 1;
}

getopts('bc:df:m:t:r') or usage();

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

if ($opt_b)
{
	$test = `uuid`;
	if (!defined($test) || $test eq "")
	{
		print "Bounce tracking requires 'uuid' command\n";
		exit 1;
	}
}

if ($opt_m)
{
	if ($opt_m =~ /,/)
	{
		$members = [];
		@lists = split(/,/,$opt_m);
		foreach $l (@lists)
		{
			if ($l =~ /^\-/)
			{
				$exclude = 1;
				$l =~ s/^\-//;
			}
			else { $exclude = 0; }
			$mems =  members_of_maillist($l);
			if ($exclude)
			{
				push @$excludes,@$mems;
			}
			else
			{
				push @$members,@$mems;
			}
		}
	}
	else
	{
		$members = members_of_maillist($opt_m);
	}
	# Name of this mailout campaign
	$campaign = $opt_m;

	foreach $u (@$excludes)
	{
		$ex{$u} = 1;
	}
	foreach $u (@$members)
	{
		$user{$u} = 1 if (!defined($ex{$u}));
	}

	$userlist = [];
	push @$userlist,(sort keys %user);

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
	# Name of this mailout campaign
	$campaign = $opt_c;
	$campaign =~ s/.*\///;

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
	if ($opt_r && /^Reply-To: /)
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

print "Would email to ",scalar(@$userlist)," users\n\n" if ($opt_d);

print "Template: $template" if ($opt_d);



# Main delivery loop

if ($opt_b && !$opt_d)
{
	tie( %BOUNCE, "DB_File","/usr/local/mail/bouncetracker.db", O_CREAT|O_RDWR,0644,$DB_HASH )
  	  || die("Can't open bouncetracker map /usr/local/mail/bouncetracker.db. Can't continue!");
	tie (%FAILURES, "DB_File", "/usr/local/mail/bounces/bounces.db",O_CREAT|O_RDWR,0644,$DB_HASH );
	foreach my $k (keys %BOUNCE)
	{
		my ($camp,$uid) = split(/:/,$k);
		$DELIVERED{$camp .":". $BOUNCE{$k}} = $k;
	}
}

$doneusers = 0;

foreach $u (@{$userlist})
{
	my $uuid;

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

	if ($opt_b)
	{
		$uuid = `uuid`;
		chomp($uuid);
		if ($DELIVERED{"$campaign:$user"})
		{
			print STDERR "Skipping $user. Already delivered\n";
			next;
		}
	}

	my $msg = $template;
	$msg =~ s/%%email%%/$user/g;
	if ($opt_m)
	{
		$msg =~ s/%%user%%/$unscopeduser/g;
		$msg =~ s/%%username%%/$unscopeduser/g;
	}
	else
	{
		foreach $k (keys %{$u})
		{
			next if ($k eq 'email');
			if ($k eq 'bulletlist')
			{
				# Special processing - expand CSV value into bullet list
				$bullets = $u->{$k};
				@ul = split(/,/,$bullets);
				my $text = join("\n   * ",@ul) . "\n";
				my $html = "";
				foreach (@ul) { $html .= "<li>$_</li>\n"; }
				$msg =~ s/%%bulletlist%%/$text/g;
				$msg =~ s/%%bulletlisthtml%%/$html/g;
			} elsif ($k eq 'jsonlist')
			{
				# Special processing of a json structure into a nested bulleted list.
				eval { 
					$jsondata = from_json($u->{$k});
				};
				if ($@)
				{
					print STDERR "Skipping $user. Error decoding JSON data: $@\n";
					next;
				}
				($text,$html) = jsonlist_to_html($jsondata,0);
				$msg =~ s/%%jsonlist%%/$text/g;
				$msg =~ s/%%jsonlisthtml%%/$html/g;
			}
			
			else {
				$val = $u->{$k};
				$msg =~ s/%%$k%%/$val/g;
			}
		}
	}

	if ($opt_b && $msg =~ /%\%tracker%%/)
	{
		$tracker = "<img src=\"https://mailmanager.its.sfu.ca/image.cgi?uuid=$uuid\" width=1 height=1>";
		$msg =~ s/%%tracker%%/$tracker/;
	}

	if ($opt_d)
	{
		print "Message for $user:\n$msg";
	}
	else
	{
		send_message("localhost",$msg,$user,$uuid);
		$DELIVERED{"$campaign:$user"} = $uuid;
		Time::HiRes::sleep(0.3);
	}
        $doneusers++;
        if (($doneusers % 10) == 0 && $opt_b)
        {
                # Flush DB to disk
                untie %BOUNCE;
                untie %FAILURES;
                tie( %BOUNCE, "DB_File","/usr/local/mail/bouncetracker.db", O_CREAT|O_RDWR,0644,$DB_HASH )
                || die("Can't open bouncetracker map /usr/local/mail/bouncetracker.db. Can't continue!");
                tie (%FAILURES, "DB_File", "/usr/local/mail/bounces/bounces.db",O_CREAT|O_RDWR,0644,$DB_HASH );
         }
}

if ($opt_b)
{
	untie %BOUNCE;
	untie %FAILURES;
}

exit 0;

sub send_message()
{
    my ($server,$msg,$recipient,$uuid) = @_;

    my $smtp = Net::SMTP->new($server);
    return undef unless $smtp;
	
	my $from = ($opt_b) ? "sfu_bounces+$uuid\@sfu.ca" : "amaint\@sfu.ca";
    my $rc = $smtp->mail($from);
    if ($rc)
    {
        $rc = $smtp->to($recipient);
        if ($rc)
        {
            $rc = $smtp->data([$msg]);
			$BOUNCE{"$campaign:$uuid"} = $recipient if ($opt_b);
			print STDERR "sent to $recipient\n";
        }
		else
		{
			print STDERR "Error for $recipient. Bad address?\n";
			if ($opt_b)
			{
				$BOUNCE{"$campaign:$uuid"} = $recipient;
				$FAILURES{$uuid} = time();
			}

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

# Convert a data structure into a bulleted list
# - If the data structure is a hash, it's considered to be bullet points with indented bullets underneath. 
#    gets passed back to this function for further interpration
# - If the data structure is an array, it's a straight array of bullet points
sub jsonlist_to_html
{
	my $data = shift;
	my $offset = shift;
	my ($text,$html);

	my $spaces = " " x (3 * ($offset+1));

	if (ref($data) eq "ARRAY")
	{
		$html = "<ul>\n";
		$text = join("\n$spaces* ",@$data) . "\n";
		foreach (@$data) { $html .= "<li>$_</li>\n"; }
		$html .= "</ul>\n";
	}
	elsif (ref($data) eq "HASH")
	{
		$html = "<ul>\n";
		foreach my $k (keys %$data)
		{
			$html .= "<li>$k\n";
			$text .= "\n$spaces* $k";
			my ($indentedtext,$indentedhtml) = jsonlist_to_html($data->{$k},$offset+1);
			$text .= $indentedtext;
			$html .= $indentedhtml . "</li>\n";
		}
		$html .= "</ul>\n";
	}
	else
	{
		$html = "<ul><li>" . $data . "</li></ul>\n";
		$text = "\n$spaces* " . $data;
	}
	return ($text,$html);
}


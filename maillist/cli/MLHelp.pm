package MLHelp;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(help);
#use lib "/usr/LOCAL/lib/ml"; 
use lib "/usr/local/mail/maillist2/cli";
use MLCLIUtils;

use constant STARTUP_HELP => "\nWelcome to the SFU Maillist facility.
Type 'help' for help; 'quit' to quit maillist.
Type 'create' to create a new maillist.
Type 'modify' to modify an existing mailist.
Type 'subscribe' to subscribe to a maillist.
Type 'unsubscribe' to unsubscribe from a maillist.
Type 'search' to search for maillists.
We recommend that you use the Web-based version of this
interface, which is at https://maillist.sfu.ca

*** Please report ANY problems you encounter to help@sfu.ca ***\n\n";

use constant GENERIC_HELP => "\nhelp <topic>                         Get help on <topic>.".
                             "\n<topic> may be one of:\n".
                             "\n    commands                         for a list of maillist commands".
                             "\n    guidelines                       for mailing list guidelines (summary)".
                             "\n    prompt                           for options available at any prompt".
                             "\n    courselist                       for help creating a courselist".
                             "\n    <command>                        for detailed description of command\n".
                             "\nAll of the commands allow you to simply enter the command name,".
                             "\nand you will be prompted for the missing information.\n".
                             "\nSFU mailing list guidelines can be found on the web at\n".
                             "\n    http://www.sfu.ca/acs-home/email/maillists/\n\n";

use constant COMMANDS_HELP => "\nAvailable Commands\n------------------\n".
                              "help [<command>]\n".
                              "quit\n".
                              "create [open|closed]\n".
                              "delete <listname>                     (list owner only)\n".
                              "info <listname>\n".
                              "members <listname>                    (list owner/manager only)\n".
                              "modify <listname> [<attribute>]       (list owner/manager only)\n".
                              "search [[<attribute>=]<value>]\n".
                              "subscribe <listname> [<address>]\n".
                              "unsubscribe <listname> [<address>]\n\n".
                              "All of the commands allow you to simply enter the command name,\n".
                              "and you will be prompted for the missing information.\n\n";
                              
use constant GUIDELINES   => "\Mailing lists are intended to be used in support of scholarly or\n".
                              "work-related activity. When a list is created, it is activated by an\n".
                              "ACS staff member. Lists that have no apparent connection to any\n".
                              "scholarly or work-related activity will not be activated.\n\n".
                              "Lists created by students will only be activated if they clearly\n".
                              "relate to course work, SFSS-recognised club, or student union.\n".
                              "The course name or club should appear in the list name.\n\n".
                              "List names\n----------\n".
                              "Mailing list names should indicate the purpose of a list. A good name\n".
                              "encourages relevant contributions, discourages irrelevant mail from\n".
                              "people who have nothing to do with the list, and generally helps to\n".
                              "keep nuisance mail to a minimum.\n\n".
                              "The following will not be activated:\n".
                              "    1. list names containing profanity.\n".
                              "    2. list names that are attempting to masquerade as some other\n".
                              "       entity in the system.\n".
                              "    3. list names that are silly, frivolous or appear to have no\n".
                              "       relationship to any scholarly activity.\n\n".
                              "Complete mailing list guidelines are available via the web at\n".
                              "    http://www.sfu.ca/acs-home/email/maillists/\n\n";
                              
use constant PROMPT_HELP =>  "\nAll of the commands allow you to simply enter the command name,\n".
                             "and you will be prompted for the missing information.\n\n".
                             "At any prompt you have the following options:\n".
                             "1. Enter the information that is requested.\n".
                             "2. Type ? and <return>, to get an explanation of the prompt.\n".
                             "3. Type \"quit\" and <return>, to abort the command.\n\n".
                             "In many cases, the prompt will also indicate a default value.\n".
                             "If you want the default value to be used, just hit return.\n".
                             "In the following example, the user is being prompted for a\n".
                             "username, and the default value is displayed in square brackets.\n\n".
                             "  maillist> search owner\n".
                             "  Enter username [robert]:                <-- user hits <return>\n".
                             "  Searching for owner=robert...\n".
                             "  ...etc.\n\n";
                             
use constant COURSELIST_HELP => "You can do basic management of existing courselists, such as adding\n".
                                "managers, and setting allowed or denied senders. \n".
                                "To create a courselist, please use the web interface at:\n\n".
                                "    https://maillist.sfu.ca \n\n";
                                
use constant CREATE_HELP => "create [open|closed|courselist]              Create a new mailing list.
 
You can specify \"open\" to indicate that it is an open list
that anyone can join, or \"closed\" to indicate that only the
list owner or manager can add members to the list. If you don't 
specify a type, you will be prompted for the type of list.
 
eg. create open                 creates an open mailing list 
  
A courselist automatically includes, as members of the list, 
addresses of students registered in a particular course. 
See 'help courselist' for information on creating and managing 
courselists.
 
The 'create' command will prompt you for a name for the list.
The name must be at least 8 chars, and no more than 32 chars, 
and must contain at least one '-' char.
 
You will be prompted to enter a description of the list. This
should be one line describing the purpose of the list. This 
description is shown when someone does a search or info command.
For an open or closed list, you will be asked whether you want
the list to be a \"restricted sender\" list. This restrictes who
can send to the list. If you reply \"no\", then anyone can send to
the list. It is recommended that closed lists should also be made
restricted sender lists.
If you make the list a restricted sender list, you will be asked whether
you want the members of the list to be able to send to it. If the list
is to be used as a normal discussion list, reply \"yes\". If you want
only a restricted set of people to send to the list, reply \"no\".
Next, you will be asked if the list should be moderated. If you
reply \"yes\", any messages sent to the list by unauthorized senders
(people who are NOT one of the allowed senders for the list) will be
will be forwarded to the owner of the list, for review.
If you reply \"no\", unauthorized senders will get an error message
explaining that they are not allowed to send to the list.
Type \"help modify\" for a description of how to edit the list of
allowed and denied senders.
Finally, if the list is open, you will be asked if email subscription
will be allowed. If you reply \"yes\" it will open the list for
subscription by anyone in the world, since it will not be necessary
to have an SFU login to subscribe to the list. People will be able
to subscribe to the list by sending an email to \"maillist@sfu.ca\"
with the subject or body of the message containing a command like
\"subscribe <list-name>\" where <list-name> is the name of your list.
You can turn this feature on or off, after the list is created, with
the \"modify <list-name> email_subscribe\" command.\n\n";

use constant DELETE_HELP => "\ndelete <listname>               Delete a mailing list you own.
 
<listname> is the name of a mailing list that you own.
 
Delete will ask for confirmation that you want to delete the
mailing list, and if you confirm deletion, the list is immediately
deleted.
 
Note: there is no undelete command! Once a mailing list has been 
deleted it cannot be restored.\n\n";

use constant INFO_HELP => "\ninfo <listname>                 Display information about a 
                                mailing list.
 
<listname> is the name of the mailing list.
 
This command displays the status, owner, managers, description, sender
options, keywords, notes, newsgroup, course and section (if it's a  
courselist), activation date and expiry date of the list.
Sender options are only displayed if it is a restricted sender list.\n\n";

use constant MEMBERS_HELP => "\nmembers <listname>              Display the full membership of
                                a mailing list.
 
<listname> is the name of the mailing list.
 
This command displays the membership of a mailing list. 
If the list is a courselist and is active, it includes the students 
who are registered in the course.
 
If the list is a closed list or a course list, only the owner or
manager of the list can display the members. If the list is open
anyone can display the membership.\n\n";

use constant MODIFY_HELP => "\nmodify <listname> [<attribute>]   Modify the specified attribute 
                                  of a mailing list.
 
modify <listname> members <filename>   Replace the members of  
                                       a mailing list with the
                                       addresses in <filename>.
 
<listname> is the name of the mailing list.
<attribute> is one of:  members
                        manager
                        description
                        welcome
                        allow
                        deny
                        restricted
                        type
                        email_subscribe
If you don't specify an attribute, you will be prompted for one.
The default attribute is \"members\".

Modify only works on mailing lists with \"defined\" or \"active\"
status.
 
Modify invokes a full-screen editor to allow you to edit the 
attribute value (with the exception of the 'type', 'restricted', and 
'email_subscribe' attributes, where you are prompted for the new information).
If you have a VISUAL environment variable set, modify will use that
editor, otherwise it will use the pico editor.
 
Use \"modify <listname> restricted\" to change the restricted sender
options of a list. You will be prompted for the new information.

Use \"modify <listname> allow\" to add addresses to the list of allowed
senders. Note that you cannot add the owner or managers of a list to
the allowed senders. The owner and managers can ALWAYS send to a list.
Allowed senders can be any combination of local addresses (with or without
the '@sfu.ca' part), external addresses, or wildcard addresses of the form
'*@domain.name'. For example, '*@sfu.ca' will allow any sfu address to send
to the mailing list.

Use \"modify <listname> deny\" to add addresses to the list of denied
senders. An address added to the denied sender list will not be able to
send to the list, even if they are a member of the list. (They will still
receive messages sent to the list, however.) Note that the owner or manager
of a list cannot be added to the denied sender list.

There is a special form of the modify command used for replacing
the members of a mailing list from a file of addresses:

    modify <listname> members <filename>
 
<filename> is the name of a file which contains the email addresses
that you want to make the members of the list. The existing members
will be replaced with the new list.

You can use \"modify <listname> type\" to change a list from open to closed
or vice versa. To change an open or closed list into a courselist, contact
maillist_admin@sfu.ca. Currently, a courselist cannot have its type changed.

Use \"modify <listname> email_subscribe\" to turn the email subscription
feature on and off. This will only work for open maillists, and it
makes the list \"open to the world\".\n\n";

use constant SEARCH_HELP => "\nsearch me                            Find and list all the mailing
                                     lists of which you are a member.
 
If you are registered in a course for which a \"courselist\" has
been set up, it will be shown. \
 
search <search string>               Find and list all the mailing
                                     lists which have a name
                                     matching the search string.
  
This is equvalent to \"search name=<search string>\".
  
search <attribute>=<search string>   Find and list all the mailing
                                     lists which have <attribute>
                                     matching the search string.
 
<attribute> is one of:  member
                        name
                        owner

<search string> is any character string. '*' can be used as a wild-
card character. For example, the search string \"sfu*\" would match 
anything that started with \"sfu\". (Don't put quotes around it, though).
String matching is case insensitive, so \"sfu\" will match \"sfu\", \"SFU\", 
\"Sfu\", etc.
 
Here are some example search commands:
search *phys*                Find all mailing lists with \"phys\" 
                             anywhere in the name.
search owner=me              Find all mailing lists owned by the
                             user logged in.
search member=ray            Find the mailing lists that you own or
                             manage that have ray as a member.
 
If you search for \"owner\", you can only specify \"me\" or your
UNIX id (or email alias) as the search argument.
If you search for \"member\", you can specify \"me\" or your
UNIX id (or email alias) to find all the lists of which you
are a member. If you specify some other user's id, the search will be
restricted to the lists which you own or manage.\n\n";

use constant SUBSCRIBE_HELP => "\nsubscribe <listname>                 Subscribe to a mailing list.
join      <listname>
 
<listname> is the name of the mailing list.
 
If you subscribe to an \"open\" list, you will be immediately added
to the mailing list membership. If you subscribe to a \"closed\" list
or a \"courselist\", a message will be sent to the mailing list owner
requesting that you be added to the list. 
 
Note that if the owner or manager of a list uses this form of the
subscribe command, they will be prompted for multiple addresses to
be added to the list. After entering the addresses, you must type
\"quit\" to quit the subscribe command.
 
subscribe <listname> <address>       Add an address to a mailing list.
                                     (Owner or manager of <listname> 
                                     only).
 
<address> must be a valid email address. The address can be for
a local user, or it can be a remote address. Some examples of 
valid local addresses are:
username@sfu.ca     Username is a valid, active CCN account (UNIX 
                    login name)
username            Equivalent to username@sfu.ca.
user_name           A valid alias for an active CCN account.
maillist-name       An existing, active maillist.
 
Note that the \"@sfu.ca\" suffix is optional for a local address.
Local addresses will be validated before they are added to the list.
 
Any address of the form user@domain which is not determined to be a 
local address is assumed to be a remote address and is added to the
mailing list. No validity checking is done on remote addresses, except
checking of address syntax.\n\n";

use constant UNSUBSCRIBE_HELP => "\nunsubscribe <listname>               Unsubscribe from a mailing list.
resign      <listname>
 
<listname> is the name of the mailing list.
 
Unsubscribe will remove your address from the list. It works on both
\"open\" and \"closed\" lists. If you have been explicitly subscribed
to a courselist by the owner, unsubscribe will work. However, if you 
are registered in a course for which a courselist exists, you
cannot unsubscribe from the list. See 'help courselist' for more
information.
 
Note that if the owner or manager of a list uses this form of the
unsubscribe command, they will be prompted for multiple addresses to
be removed from the list. After entering the addresses, you must type
\"quit\" to quit the unsubscribe command.
 
unsubscribe <listname> <username>   Unsubscribe another user from a
                                    mailing list. (Owner or manager
                                    of <listname> only).
 
<username> is the UNIX account or email alias of the person to be
removed from the mailing list.\n\n";

use constant TRANSFER_HELP => "\nTo transfer ownership of a list, use the web interface at:
    https://maillist.sfu.ca \n\n";
    
use constant MENU_HELP => "\nThe \"menu\" command is a simplified, menu-driven interface to 
the maillist commands.\n\n";
    
sub help {
    my ($topic) = @_;
    for ($topic) {
        /^startup$/ and do { print STARTUP_HELP; last; };
    	/^commands$/ and do { more(COMMANDS_HELP); last; };
    	/^guidelines$/ and do { more(GUIDELINES); last; };
    	/^prompt$/ and do { more(PROMPT_HELP); last; };
    	/^courselist$/ and do { print COURSELIST_HELP; last; };
    	/^help$/ and do { print GENERIC_HELP; last; };
    	/^create$/ and do { more(CREATE_HELP); last; };
    	/^delete$/ and do { print DELETE_HELP; last; };
    	/^info$/ and do { print INFO_HELP; last; };
    	/^members$/ and do { print MEMBERS_HELP; last; };
    	/^modify$/ and do { more(MODIFY_HELP); last; };
    	/^menu$/ and do { more(MENU_HELP); last; };
    	/^search$/ and do { more(SEARCH_HELP); last; };
    	/^subscribe$/ and do { more(SUBSCRIBE_HELP); last; };
    	/^unsubscribe$/ and do { more(UNSUBSCRIBE_HELP); last; };
    	/^transfer$/ and do { print TRANSFER_HELP; last; };
    	if ($topic) {
    	   print "No help available for \"$topic\".";
    	} else {
    	   print GENERIC_HELP;
    	}
    	last;
    }
}

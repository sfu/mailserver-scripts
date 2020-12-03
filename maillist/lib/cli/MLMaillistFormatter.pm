package MLMaillistFormatter;

require Exporter;
@ISA    = qw(Exporter);
# Find the lib directory above the location of myself. Should be the same directory I'm in
# # This isn't necessary if these libs get installed in a standard perl lib location
use FindBin;
use lib "$FindBin::Bin/..";
use MLRestMaillist;


sub new {
	my $class = shift;
    my $maillist = shift;
    my $self = {};
    bless $self;
    $self->{MAILLIST} = $maillist;
    return $self;
}


sub display {
  my $self = shift;
  
  my $type;
  my $res = "Unrestricted sender";
  my $list = $self->{MAILLIST};
  
  if ($list->isCourselist()) {
    $type = "courselist";
  } else {
    if ($list->isOpen()) { $type = 'open'; }
    else { $type = 'closed'; }
  }

  $res = 'Restricted sender' if $list->isRestricted();
  my $ats = $list->membersAllowedToSend() ? "Members allowed to send" : '';
  my $email = $list->subscribeByEmail ? "Anyone can subscribe via email" : '' ;
  
  my $managers = $self->_managerString();
  my $desc = $list->description();
  
  format LISTINFO =
List Name:    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $list->name()
Status:       @<<<<<<<<<<<<<<
              $list->status()
Type:         @<<<<<<<<<<<<<<
              $type
Owner:        @<<<<<<<<
              $list->owner()
Manager@<<:   ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
       "(s)"  $managers
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $managers
Description:  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $desc
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $desc
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< ...
              $desc
Options:      ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $res
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $ats
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $email
Activated On: @<<<<<<<<<
              $list->actdate()
~Expires On:   @<<<<<<<<<
              $list->expdate()
              
.
  STDOUT->format_name("LISTINFO");
  write;
  STDOUT->format_name("STDOUT");
  
}

sub _managerString {
  my $self = shift;

  my $managersRef = $self->{MAILLIST}->managers();
  if ($managersRef==0) {
    return "";
  } else {
    my @managers = @$managersRef;
    unless (scalar(@managers)) {
      return "(No managers assigned)";
    }
    return (join ', ',@managers)."  (".$self->{MAILLIST}->name()."-request)";
  }
}


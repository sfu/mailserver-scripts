package MLMaillist;

require Exporter;
@ISA    = qw(Exporter);
#use lib "/usr/LOCAL/lib/ml";
use lib "/usr/local/mail/maillist2/cli";
use MLMP1Server;

@KEYS = qw(name type status owner actdate expdate newsfeed desc opt ats mod email);
@MANAGERS = undef;

sub new {
    my $class = shift;
    my $info  = shift;
    my $service = shift;
	my $self = {};
	bless $self, $class;
	$self->{MLSERVICE} = $service;
	#print "$info\n" if DEBUG;
	@$self{@KEYS} = split /:/,$info;
	$self->{ats} = ($self->{ats} eq 'true') ? 1 : 0;
	return $self;
}

	
sub name {
	my $self = shift;
	return $self->{name};
}

sub status {
	my $self = shift;
	return $self->{status};
}

sub type {
	my $self = shift;
	return $self->{type};
}

sub owner {
	my $self = shift;
	return $self->{owner};
}

sub actdate {
	my $self = shift;
	return $self->{actdate};
}

sub expdate {
	my $self = shift;
	return $self->{expdate};
}

sub newsfeed {
	my $self = shift;
	return $self->{newsfeed};
}

sub description {
	my $self = shift;
	return $self->{desc};
}

sub options {
	my $self = shift;
	return $self->{opt};
}

sub allowedToSend {
	my $self = shift;
	return $self->{ats};
}

sub moderated {
	my $self = shift;
	return $self->{mod};
}

sub subscribeByEmail {
	my $self = shift;
	return $self->{email};
}

sub isCourselist {
	my $self = shift;
	return $self->{type} eq 's';
}

sub isOpen {
	my $self = shift;
	return $self->{type} eq 'o';
}

sub isClosed{
	my $self = shift;
	return $self->{type} eq 'c';
}

sub isRestricted{
	my $self = shift;
	return $self->{opt} =~ 'r';
}

sub set {
  my $self = shift;
  my $value = shift;
  my $key  = shift;
  my $service = $self->{MLSERVICE};
  #print "set:key=$key;value=$value\n" if DEBUG;
  my $result = $service->set($self->{name}, $value, $key);
  #print "set:result:$result\n" if DEBUG;
  print $service->error()."\n" unless $result;
  return 0 unless $result;
  $self->_update();
  return 'ok';  
}

sub get {
  my $self = shift;
  my $key  = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->get($self->{name}, $key);
  #print "get:result:$result\n" if DEBUG;
  print $service->error()."\n" unless $result;
  return 0 unless $result;
  return $result;  
}

sub note {
  my $self = shift;
  my $value;
  my $service = $self->{MLSERVICE};
  $value = $self->get("note");
  if ($value==0) {
	print $service->error()."\n";
	return undef;
  } else {
	return $value;
  }
}

sub isManager {
  my $self = shift;
  my $man = shift;
  my $managers = $self->managers();
  return grep( $man, @$managers ) if $managers;
  return 0;
}

sub managers {
  my $self = shift;
  my $managersRef;
  my $service = $self->{MLSERVICE};
  unless ($self->{mngrs}) {
	  $managersRef = $service->managers($self->{name});
      if ($managersRef==0) {
        print $service->error()."\n";
        return undef;
      } else {
        my @sorted = sort @{$managersRef};
        $self->{mngrs} = \@sorted;
      }
   }
   return $self->{mngrs};
}

sub addManager {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->add($self->{name}, "manager", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}
  
sub deleteManager {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->remove($self->{name}, "manager", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}

sub allowedSenders {
  my $self = shift;
  my $ref;
  my $service = $self->{MLSERVICE};
  unless ($self->{allowedSenders}) {
	  $ref = $service->allowedSenders($self->{name});
      if ($ref==0) {
        print $service->error()."\n";
        return undef;
      } else {
        my @sorted = sort @{$ref};
        $self->{allowedSenders} = \@sorted;
      }
   }
   return $self->{allowedSenders};
}

sub addAllowed {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->add($self->{name}, "allow", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}
  
sub deleteAllowed {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->remove($self->{name}, "allow", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}

sub deniedSenders {
  my $self = shift;
  my $ref;
  my $service = $self->{MLSERVICE};
  unless ($self->{deniedSenders}) {
	  $ref = $service->deniedSenders($self->{name});
      if ($ref==0) {
        print $service->error()."\n";
        return undef;
      } else {
        my @sorted = sort @{$ref};
        $self->{deniedSenders} = \@sorted;
      }
   }
   return $self->{deniedSenders};
}

sub addDenied {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->add($self->{name}, "deny", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}
  
sub deleteDenied {
  my $self = shift;
  my $address = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->remove($self->{name}, "deny", $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}



sub display {
  my $self = shift;
  my $type;
  my $res = "Unrestricted sender";
  #my ($name,$t,$status,$owner,$act,$exp,$news,$desc,$opt,$ats,$mod,$email) = split /:/,$info;
  my $t = $self->{type};
  if ($t eq "c") { $type = "closed"; }
  elsif ($t eq "o") {$type = "open"; }
  elsif ($t eq "s") {$type = "courselist"; }
  else { $type = $t; }
  
  $res = 'Restricted sender' if ($self->{opt} eq 'r');
  my $ats = $self->{ats} ? "Members allowed to send" : "";
  my $email = $self->{email} ? "Anyone can subscribe via email" : "" ;
  
  my $managers = $self->_managerString();
  
  format LISTINFO =
List Name:    @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $self->{name}
Status:       @<<<<<<<<<<<<<<
              $self->{status}
Type:         @<<<<<<<<<<<<<<
              $type
Owner:        @<<<<<<<<
              $self->{owner}
Manager@<<:   ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
       "(s)"  $managers
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $managers
Description:  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $self->{desc}
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $self->{desc}
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< ...
              $self->{desc}
Options:      ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $res
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $ats
~             ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
              $email
Activated On: @<<<<<<<<<
              $self->{actdate}
~Expires On:   @<<<<<<<<<
              $self->{expdate}
              
.
  STDOUT->format_name("LISTINFO");
  write;
  STDOUT->format_name("STDOUT");
  
}

sub _managerString {
  my $self = shift;
  my $managersRef = $self->managers();
  if ($managersRef==0) {
    return "";
  } else {
    my @managers = @$managersRef;
    unless (scalar(@managers)) {
      return "(No managers assigned)";
    }
    return (join ', ',@managers)."  (".$self->{name}."-request)";
  }
}

sub members {
  my $self = shift;
  my $membersRef;
  my $service = $self->{MLSERVICE};
  unless ($self->{members}) {
	  $membersRef = $service->members($self->name());
      if ($membersRef==0) {
        print $service->error()."\n";
        return 0;
      } else {
        my @sorted = sort @{$membersRef};
        $self->{members} = \@sorted;
      }
   }
   return $self->{members};
}

sub courseMembers {
  my $self = shift;
  return [] unless $self->isCourselist();
  my $membersRef;
  my $service = $self->{MLSERVICE};
  unless ($self->{courseMembers}) {
	  $membersRef = $service->courselist($self->{name});
      if ($membersRef==0) {
        print $service->error()."\n";
        return 0;
      } else {
        my @sorted = sort @{$membersRef};
        $self->{courseMembers} = \@sorted;
      }
   }
   return $self->{courseMembers};
}

sub subscribe {
  my $self = shift;
  my $address = shift;
  #print "In MLMaillist->subscribe $address\n" if DEBUG;
  my $service = $self->{MLSERVICE};
  my $result = $service->subscribe($self->{name}, $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}

sub unsubscribe {
  my $self = shift;
  my $address = shift;
  #print "In MLMaillist->unsubscribe $address\n" if DEBUG;
  my $service = $self->{MLSERVICE};
  my $result = $service->unsubscribe($self->{name}, $address);
  print $service->error()."\n" unless $result;
  return $result ? 'ok' : 0;
}

sub _update() {
  my $self = shift;
  my $service = $self->{MLSERVICE};
  my $result = $service->search("name",$self->{name});
  my $maillist = @{$result}[0] if $result;
  #print "_update:new maillist:\n" if DEBUG;
  #$maillist->display() if DEBUG;
  @$self{@KEYS} = @$maillist{@KEYS};
  return 1;
}

  

package MLCLIUtils;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(askfor askforreturn askforwithdefault confirm display_lists editfile getBoolean promptAndGetReply mlPrintArray more getCurrentAndNextSemester);

use constant FILL   => "  .  .  .  .  .  .  .  .  .  .  .";
use constant DEFAULTEDITOR => 'pico';


sub askfor {
  my ($prompt,$helpmsg,$returnhelp) = @_;
  my $tmpprompt = $prompt;
  $tmpprompt .= ": ";
  my $buf = "";
  my $loopcount = 0;
  
  until ($buf) {
    print $helpmsg if ($loopcount++ == 2 && $helpmsg);
    print $tmpprompt;
    $buf=<STDIN>;
    $buf =~ s/\s*$//;
    if ($buf eq '?' || $buf eq 'help') {
      print "$helpmsg\n" if $helpmsg;
      $loopcount = 0;
      $buf = "";
    } elsif ($buf eq 'quit' || $buf eq 'exit' || $buf eq 'bye' || $buf eq 'abort' || $buf eq 'cancel') {
        $buf = 'quit';
    }
  }
  return $buf;
}

sub askforreturn {
  print "\nPress the ENTER key to continue...";
  my $buf=<STDIN>;
  return;
}

sub askforwithdefault {
  my ($prompt,$default,$helpmsg,$returnhelp) = @_;
  my $tmpprompt = $prompt;
  $tmpprompt .= " [$default]" if $default;
  $tmpprompt .= ": ";
  my $buf = "";
  my $loopcount = 0;
  
  until ($buf) {
    print $helpmsg if ($loopcount++ == 2 && $helpmsg);
    print $tmpprompt;
    $buf=lc <STDIN>;
    $buf =~ s/\s*$//;
    if ($buf eq '?' || $buf eq 'help') {
      print "$helpmsg\n" if $helpmsg;
      $loopcount = 0;
      $buf = "";
    } elsif ($buf eq "") {
      $buf = $default if $default;
    } elsif ($buf eq 'quit' || $buf eq 'exit' || $buf eq 'bye' || $buf eq 'abort' || $buf eq 'cancel') {
        $buf = 'quit';
    }
  }
  return $buf;
}

sub confirm {
  my ($prompt,$default,$helpmsg,$returnhelp) = @_;
  $default = 'no' unless $default;
  $helpmsg = "Enter 'y' or 'yes' to answer yes; 'n' or 'no' to answer no;\nor 'quit' to abort the command.\n\n" unless $helpmsg;
  my $buf = "";
  until ($buf) {
     $buf = lc askforwithdefault($prompt,$default,$helpmsg,$returnhelp);
     return -1 if $buf eq "quit";
     if ($buf =~ /^(y|ye|yes)$/) {
        $buf = "y";
     } elsif ($buf =~ /^(n|no)$/) {
        $buf = "n";
     } else {
        print "I don't know what \"$buf\" means. Please reply with  'yes', 'no', or 'quit'.\n\n";
     }
  }
  return $buf;
}

sub display_lists {
  my @lists = @_;
  my $rows = scalar(@lists);
  if ($rows) { print "$rows matched.\n"; }
  else { print "Nothing matched.\n" ; }
  
  open MULTILIST, ">/tmp/ml$$";
  foreach $list (@lists) {
    my $name = $list->name();
    $name .= " ";
    $name .= substr(FILL,-(32-length($name)));
    my $desc = $list->description();
    my $type = 'c';
    $type = 'o' if $list->type() eq 'o';
    format MULTILIST = 
@ @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$type, $name,                      $desc
~                                  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
                                   $desc
~                                  ^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<...
                                   $desc
.
    write MULTILIST;
  }
  close MULTILIST;
  if ($main::oneoff) {
    system "cat /tmp/ml$$";
  } else {
    system "more /tmp/ml$$";
  }
  unlink "/tmp/ml$$";
}

sub more {
  my ($data) = @_;
  my $fn = "/tmp/mlmore$$";
  open TMPFILE,  ">$fn";
  print TMPFILE "$data";
  close TMPFILE;
  system "more $fn";
  unlink "$fn";
}
  
sub getBoolean {
  my ($prompt,$default,$help) = @_;
  my $value = confirm( $prompt, $default, $help, 0 );
  return -1 if $value eq "quit";
  return $value eq "y";
}

sub mlPrintArray {
  my @rows = @_;
  open TMPFILE,  ">/tmp/ml$$";
  foreach $row (@rows) {
    print TMPFILE "$row\n";
  }
  close TMPFILE;
  if ($main::oneoff) {
    system "cat /tmp/ml$$";
  } else {
    system "more /tmp/ml$$";
  }
  unlink "/tmp/ml$$";
}

sub promptAndGetReply {
  my ($prompt) = @_;
  print $prompt;
  my $buf=<STDIN>;
  $buf =~ s/\s*$//;
  $buf =~ s/^\s*//;
  return split /\s+/,$buf;
}

sub editfile {
  my ($filename) = @_;
  my $tmp = getEditor();
  return -1 if $tmp == -1;
  my @args = split /\s+/,$tmp;
  if ($args[0] eq 'pico') {
    push @args,'-t' unless grep '-t', @args;
  } elsif ($args[0] =~ /^bbedit/) {
    push( @args,'-w') unless grep /-w/, @args;
  }
  push @args,$filename;
  return 0xffff & system @args;
}

sub getEditor {
  my $editor = $ENV{VISUAL};
  $editor = $ENV{EDITOR} unless fileInPath($editor);
  return $editor if fileInPath($editor);
  return DEFAULTEDITOR if (fileInPath(DEFAULTEDITOR));
  # env variable not set and default editor not available. Prompt for editor.
  while (1) {
    $editor = askforwithdefault("Enter the name of an editor", "", "\nYou do not have a VISUAL or EDITOR environment variable set.\nEnter the name of your preferred text editor.\n\n", 0);
    next unless $editor;
    return -1 if $editor =~ /^quit/;
    return $editor if fileInPath($editor);
    print "Can't find ".$editor." in your PATH.\n\n";
  }
}

sub fileInPath {
  my ($filename) = @_;
  return 0 unless $filename;
  my @PATH = split /:/,$ENV{PATH};
  foreach $path (@PATH) {
    return 1 if -e "$path/$filename";
  }
  return 0;
}
  
sub getCurrentAndNextSemester() {
        my @sems = ("1","1","1","1", "4", "4", "4", "4", "7",  "7", "7", "7","7"
, "1","1","1","1");
        my $year = (localtime)[5];
        my $month = (localtime)[4];
        my $sem = $sems[$month];
        my $current = "$year"."$sem";
        $sem = $sems[$month+4];
        if ($month+4>11) { $year++; }
        my $next    = "$year"."$sem";
        return ($current,$next);
}


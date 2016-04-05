package MLUtils;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( _sleep _stdout _stderr _sendMail _altSendMail _sendExtras );

sub _sleep {
    my $time = 900;
    $main::sleepCounter++;
    if ($main::sleepCounter < 3) { $time = 30; }
    elsif ($main::sleepCounter < 5) { $time = 300; }
    sleep $time;
}

sub _stdout($) {
    my ($line) = @_;

    print STDOUT scalar localtime() . " $line\n";
}

sub _stderr($) {
    my ($line) = @_;

    print STDERR scalar localtime() . " $line\n";
}

sub _sendMail {
    my ($to, $subject, $body, $from) = @_;
    if ($main::TEST) {
      print "Sending mail:\n";
      print "to: $to\n";
      print "from: $from\n";
      print "subject: $subject\n";
      print "body: $body\n";
    }
    if ($main::DELIVER) {
    	my $sendmail = '/usr/lib/sendmail';
    	open(MAIL, "|$sendmail -oi -t");
    	print MAIL "Precedence: list\n";
    	print MAIL "From: $from\n";
        print MAIL "Reply-To: noreply\@sfu.ca\n";
    	print MAIL "To: $to\n";
    	print MAIL "Subject: $subject\n\n";
    	print MAIL "$body\n";
    	close(MAIL);
    }
}

sub _altSendMail {
    my ($to, $subject, $body, $from) = @_;
    if ($main::TEST) {
      print "Sending mail:\n";
      print "to: $to\n";
      print "from: $from\n";
      print "subject: $subject\n";
      print "body: $body\n";
    }
    if ($main::DELIVER) {
    	my $sendmail = '/usr/lib/sendmail-vacation';
    	open(MAIL, "|$sendmail -oi -t");
    	print MAIL "Precedence: list\n";
    	print MAIL "From: $from\n";
        print MAIL "Reply-To: noreply\@sfu.ca\n";
    	print MAIL "To: $to\n";
    	print MAIL "Subject: $subject\n\n";
    	print MAIL "$body\n";
    	close(MAIL);
    }
}

sub _sendExtras {
    my ($to, $subject, $body, $from, %xheaders) = @_;
    if ($main::TEST) {
      print "Sending mail:\n";
      foreach $xhdr (keys %xheaders) {
          print "$xhdr: ".$xheaders{$xhdr}."\n";
      }
      print "to: $to\n";
      print "from: $from\n";
      print "subject: $subject\n";
      print "body: $body\n";
    }
    if ($main::DELIVER) {
        my $sendmail = '/usr/lib/sendmail-vacation';
        open(MAIL, "|$sendmail -oi -t");
        print MAIL "Precedence: list\n";
        foreach $xhdr (keys %xheaders) {
            print MAIL "$xhdr: ".$xheaders{$xhdr}."\n";
        }
        print MAIL "From: $from\n";
        print MAIL "Reply-To: noreply\@sfu.ca\n";
        print MAIL "To: $to\n";
        print MAIL "Subject: $subject\n\n";
        print MAIL "$body\n";
        close(MAIL);
    }
}    


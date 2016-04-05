package MLUtils;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( _sleep _stdout _stderr _sendMail _altSendMail );

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

# sub getFromMaillist {
#    my ($cmd,$argstring) = @_;
#    my $content = "";
#    my $i=0;
#    my $pattern = "^ok $cmd";
#    my $url = BASEURL . $cmd . "?" . $argstring;
#    _stdout( "Getting $url" ) if $main::TEST;
# GET:
#    for ($i=0;$i<2;$i++) {
#       $content = getFromURL($url);      
#       if ($content =~ /$pattern/i) {
#          my $start = length("ok $cmd") +1;
#          return substr($content, $start);
#       }
#       syslog("warning","%s getFromURL for $url returned $content", $main::ID );
#       _stderr( "%s getFromURL for $url returned $content", $main::ID );
#       sleep 30;
#       next GET;
#    }
# }
# 
# sub getFromURL {
#    my ($url) = @_;
#    my $i = 0;
#    my $ua = LWP::UserAgent->new;
#    $ua->timeout(90);
# GET:
#    for (;;) {
#      # ua->get catches the die issued by the SIGTERM handler, so
#      # I have the handler set MLD::TERM, then test it after the call to get.
#      $MLD::TERM = 0;
#      my $response = $ua->get($url);
#      if ($response->is_success) {
#        $main::sleepCounter = 0;
#        return $response->content;
#      }
#      die "Child $$ interrupted" if ($MLD::TERM);
#      _stderr( "${main::ID} get for $url not successful:". $response->code );
#      _sleep();
#      next GET;
#    }
# }


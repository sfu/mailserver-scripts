package Utils;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( validSFUID validName cleanName validPhone cleanPhone validHours xtrim _sleep _stdout _stderr _sendMail _altSendMail );

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

sub validSFUID
{
        local($sn_l) = @_;
        if (length($sn_l) != 9)
        {
            print "Incorrect number of digits in student #:$sn_l\n";
            return 0;
        }
        if ($sn_l !~ /^[0-9]*$/)
        {
            print "Non-numeric characters in student #:$sn_l\n";
            return 0;
        }
        return 1;
}

sub validName
{
        local($name_l, $min_length, $max_length) = @_;
        my $name_ll;

        if (length( $name_l ) < $min_length)
        {
            print "Name is too short:$name_l\n";
            return 0;
        }
        if (length( $name_l ) > $max_length)
        {
            print "Name is too long:$name_l\n";
            return 0;
        }
        # Disregard anything after ( or / or ,
        ($name_ll, $dummy) = split(/[\(\/\,]/,$name_l,2);

        if ($name_ll !~ /^[0-9a-zA-Z \'\-\.\,]*$/)
        {
            print "Invalid character in name:$name_l\n";
            return 0;
        }
        return 1;
}

sub cleanName {
    my ($name) = @_;
    my $dummy;
    # Disregard anything after ( or / or ,
    ($name, $dummy) = split(/[\(\/\,]/,$name,2);
    # Disregard anything after numbers
    ($name, $dummy) = split /[0-9]/,$name,2;
    # Remove '.' chars
    $name = join '', split /\./,$name;
    # Turn whitespace into single spaces
    $name = join ' ', split /\s/,$name;
    return $name;
}

sub cleanPhone
{
        local($phone_l) = @_;

        if ($phone_l !~ /^[0-9 \-]*$/) {
            $phone_l = "";
        }
        return $phone_l;
}

sub validPhone
{
        local($phone_l) = @_;

        if ($phone_l !~ /^[0-9 \-]*$/)
        {
            print "Invalid character in phone #:$phone_l\n";
            return 0;
        }
        return 1;
}

sub validHours
{
        local($hours_l) = @_;

        if ($hours_l !~ /^[0-9]*$/)
        {
            print "Non-numeric characters in credit-hours:$hours_l\n";
            return 0;
        }
        return 1;
}

# Function for left trimming and right trimming a string
sub xtrim
{
        ($var_l) = @_;
        $var_l =~ s/^\s+(\S)/$1/;
        $var_l =~ s/(\S)\s+$/$1/;
        return $var_l;
}

1;
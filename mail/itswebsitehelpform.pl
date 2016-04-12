#!/usr/bin/perl

my $msg;
while (<>) {
        $msg .= $_
}
my $tempDir = '/tmp/';
my $currentTS = time();
my $randNum = int( rand( 10000 ) );
my $tempFile = $tempDir . $currentTS . "-" . $randNum;
open (TMPFILE, ">$tempFile");

# Change From: header to be value of contact_email field
if ($msg =~ /contact_email : \n^([0-9A-Za-z._%+-]+@[0-9A-Za-z.-]+\..*)/m) {
        my $from = $1;
        $msg =~ s/donotreply\@sfu.ca/$from/mg;
}

# Change Subject: header to be value of subject field
if ($msg =~ /^subject : \n(.+)$/m) {
        my $subject = $1;
        $msg =~ s/^Subject:.*$/Subject: $subject/m;
}

# If a rt_to address was specified, send the message along to that address; otherwise, pipe it into rt-mailgate
if ($msg =~ /rt_to : \n^([0-9A-Za-z._%+-]+\@sfu.ca)/m) {
        $new_to = "To: \"$1\" <$1>";
        $msg =~ s/^To: .*$/$new_to/m;
        print TMPFILE $msg;
        close(TMPFILE);
        `cat $tempFile | /usr/sbin/sendmail -t`;
} else {
        print TMPFILE $msg;
        close(TMPFILE);
        `cat $tempFile | /etc/smrsh/rt-mailgate --queue 'ITS - CaRS - ITS Client Support' --action correspond --url 'https://rt.sfu.ca'`;
}

unlink($tempFile);

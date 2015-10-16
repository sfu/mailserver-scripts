#!/usr/local/bin/perl

use lib '/opt/mail/maillist2/bin/test';
use LOCK;

my $LOCK = shift;
$main::TEST = 1;

FORK:
if ($pid = fork) {
    # parent
    my $i = 0;
    while($i++<4000) {
        acquire_lock($LOCK);
        release_lock($LOCK);
    }
} elsif (defined $pid) {
    # child
    my $i = 0;
    while($i++<4000) {
        acquire_lock($LOCK);
        release_lock($LOCK);
    }
} else {
    die "Fork error: $!\n";
}

#!/usr/local/bin/perl

while (<>) {
	chomp;
	($n,$pwd,$u,$g,$q,$c,$gcos,$d,$s) = getpwnam $_;
	print "$gcos <$_\@sfu.ca>\n";
}

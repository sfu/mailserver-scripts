#!/usr/local/bin/perl

#---
#--- This is a simple barebones script for deleting files from a
#--- particular directory, matching a certain pattern, which haven't
#--- changed for x days
#---
use strict;

$main::SYSBIN='/usr/bin';

#--- Get arguments
my $dir=$ARGV[0];
my $pattern=$ARGV[1];
my $numdays=$ARGV[2];

#--- Exit if no arguments
if ($dir eq "")
{
  print "\n";
  print "**Error: missing directory argument\n";
  exit;
}

opendir(DIR,$dir);
my @filenames=readdir(DIR);
closedir(DIR);

my $mintime=86400*$numdays;

my $ff;
my $file;
my $timediff;
my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);

#--- Process each file name in the list
foreach $ff (@filenames)
{
  if ($ff eq '.' || $ff eq '..') {next;}
  if ($pattern eq '' || $ff =~ /${pattern}/)
  {
    $file="$dir/$ff";
    ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,
     $blksize,$blocks) = stat($file);
    if ($uid eq "") {next;}
    $timediff=time-$mtime;
    if ($timediff > $mintime)
    {
      system "${main::SYSBIN}/rm -f $file";
    }
  }
}

exit;

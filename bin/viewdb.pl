#!/usr/bin/perl

use DB_File;

$file = shift;

if (!$file || $file eq "")
{
	print "Usage: viewdb dbname\n";
}

if (! -f "$file.db")
{
	print "$file.db doesn't exist\n";
	exit 1;
}

tie %db, 'DB_File', "$file.db", O_RDONLY, 0660;

foreach $k (keys %db)
{
    print "$k: ",$db{$k},"\n";
}

untie %db;


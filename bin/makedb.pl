#!/usr/bin/perl

use DB_File;


$file = shift;

if (!$file || $file eq "")
{
	print "Usage: dbmake dbname\nIf 'dbname' exists as a flat file (no .db suffix), use its contents to create db file\nOtherwise create empty db file\n";
}

if (-f $file)
{
	open (IN, $file);
	$read=1;
}

if (-f "$file.db")
{
	print "$file.db already exists. Won't overwrite\n";
	exit 1;
}

tie %db, 'DB_File', "$file.db", O_CREAT|O_RDWR, 0660;
if ($read)
{
	while(<IN>)
	{
		chomp;
		($k,$v) = split(/:?\s+/,$_,2);
		$db{$k} = $v;
	}
	close IN;
}

untie %db;


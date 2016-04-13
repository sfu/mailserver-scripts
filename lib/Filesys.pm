package Filesys;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(migrateaccount makedir copyfile dircpy dirbak dirarc filearc backup_and_delete_directory get_current_vol get_filesys get_available_space recursive_delete runscript delete_account_files delete_archive_files archiveuser dir_contains_non_excluded_files isexcluded);
use File::Copy;
use English;
use constant TAR => "/bin/gtar";
$BAKDIR = "/home_/bak";
$EXCLUDED = "/usr/local/adm/amaint/excluded";

# Migrate a home directory from one volume to another
# Parameters: 	user		the userid to be migrated.
#		physhome	the new physical volume
#		uid		the uid for the user
#		gid		the default gid for the user
# Returns 1 if successful, 0 if an error occurred.
# Note: if the new directory gets created ok, but the delete of the old 
#	directory fails, 1 will still be returned, and an error message will
#	be printed. The old directory should be manually backed up and deleted.

sub migrateaccount {
	($user,$physhome,$uid,$gid) = @_;

	$homelink = "/home/".$user;
	if (!-d $BAKDIR) {
		if (!mkdir( $BAKDIR, 0700 )) {
			printf( "Can't create backup dir.\n" );
			return 0;
		}
	}

	$current_homedir = get_current_vol( $user );
	if ($current_homedir eq "") {
		printf( "Can't read old homedir link for $user.\n" );
		return 0;
	}

	if ($physhome eq $current_homedir) {
		printf( "$user already on target volume.\n" );
		return 1;
	}

	if (-d $physhome) {
		printf( "The directory $physhome already exists.\n" );
		return 0;
	}

	if (!makedir( $physhome, 0711, $uid, $gid )) {
		printf( "Couldn't make new home dir: $physhome\n" );
		return 0;
	}

	if (!dircpy( $physhome, $current_homedir )) {
		rmdir $physhome;
		printf( "Copy from $current_homedir to $physhome failed.\n" );
		return 0;
	}

	if (!unlink $homelink) {
		printf( "Couldn't unlink $homelink\n" );
		return 0;
	}

	if (!symlink( $physhome, $homelink )) {
		printf( "Couldn't symlink to $physhome.\n" );
		return 0;
	}

	if (!backup_and_delete_directory( $current_homedir, $user )) {
		printf( "Error backing up old home dir: $current_homedir\n" );
	}

	return 1;

}

# Create a new directory with specified owner, group, and mode
# Parameters:	dir	Path to the directory
#		mode	Mode of the directory
#		uid	owner
#		gid	group
# Returns 1 if successful, 0 if an error occurred.

sub makedir {
	my ($dir,$mode,$uid,$gid) = @_;

	if (!mkdir( $dir, $mode )) {
		printf( "Couldn't create $dir.\n" );
		return 0;
	}

	if ($REAL_USER_ID == 0) {
		if (chown( $uid, $gid, $dir ) != 1) {
			printf( "Couldn't chown $dir.\n" );
			return 0;
		}
	}
	return 1;
}

# Copy a file
# Parameters:	file	The name of the file to copy
#		fromdir	The directory which contains file
#		todir	The directory to which you want to copy file.
#		uid	The owner of the file.
#		gid	The group of the file.

sub copyfile {
	my ($file, $fromdir, $todir, $uid, $gid) =@_;

	if (!copy( "$fromdir/$file", "$todir/$file" )) { 
		printf( "Copy from $fromdir/$file to $todir/$file failed\n" );
		return 0; 
	}
	if ($REAL_USER_ID == 0) {
		if (chown( $uid, $gid, "$todir/$file" ) != 1) {
			printf( "Couldn't chown $todir/$file.\n" );
			return 0;
		}
	}
	return 1;
}

# Copy a whole directory using tar
# Parameters:	destdir		the destination directory
#		sourcedir	the existing (source) directory
# The syntax of dircpy is the same as the c strcpy command, except
# it works on a directory. If destdir does not exist, dircpy creates it.
# dircpy returns 1 if it successfully copied the directory, 0 otherwise.

sub dircpy {
	my ($destdir, $sourcedir) = @_;
	if (!-d $destdir) { 
		if (!makedir( $destdir, 0700, $REAL_USER_ID, $REAL_GROUP_ID )) {
			printf "Couldn't create $destdir.\n"; 
			return 0;
		}
	}
	if (-d $sourcedir) {
		$script = "#!/bin/sh\n".TAR." cf - -C $sourcedir . | (cd $destdir; ".TAR." xfBp -)\n";
		return runscript( $script );
	}
	else {
		printf( "dircpy: $sourcedir is not a directory.\n" );
		return 0;
	}
}

# Tar a directory 
# Parameters:	destfile	the destination tar file
#		sourcedir	the existing (source) directory
#		excludefile	the name of a file containing an exclude list
# dirbak will not overwirte an existing destfile.
# dirbak returns 1 if it successfully copied the directory, 0 otherwise.

sub dirbak {
	my ($destfile, $sourcedir, $excludefile) = @_;
	if (-e $destfile) {
		printf( "dirbak: $destfile already exists.\n" );
		return 0;
	}
	if (-d $sourcedir) {
		if ($excludefile) {
			$script = "#!/bin/sh\n".TAR." cfX - $excludefile -C $sourcedir . >$destfile\n";
		}
		else {
			$script = "#!/bin/sh\n".TAR." cf - -C $sourcedir . >$destfile\n";
		}
		return runscript( $script );
	}
	else {
		printf( "dirbak: $sourcedir is not a directory.\n" );
		return 0;
	}
	return 1;
}

# Archive a directory using tar and gzip 
# Parameters:	destfile	the destination filename (do not include
#				.tar extension.
#		sourcedir	the existing (source) directory
# dirarc will not overwrite an existing destfile.
# dirarc returns 1 if it successfully copied the directory, 0 otherwise.

sub dirarc {
	my ($destfile, $sourcedir) = @_;
	$ARCHIVEVOL = "/home_";

	if ($destfile eq "") {
		printf( "dirarc: $destfile not supplied.\n" );
		return 0;
	}
	if (-e "/tmp/$destfile.tar") { unlink "/tmp/$destfile.tar"; }
	if (-e "/tmp/$destfile.tar.gz") { unlink "/tmp/$destfile.tar.gz"; }

	if (-d $sourcedir) {
		if (!dirbak( "/tmp/$destfile.tar", $sourcedir, $EXCLUDED )) {
			printf( "dirarc: tar of $sourcedir failed.\n" );
			return 0;
		}

		if (!filearc( "$destfile.tar", "$destfile.tar", "/tmp" )) {
			printf( "dirarc: archive of $sourcedir failed.\n" );
			return 0;
		}
		
	}
	else {
		printf( "dirarc: $sourcedir is not a directory.\n" );
		return 0;
	}

	unlink "/tmp/$destfile.tar";
	return 1;
}

# Archive a file using gzip 
# gzips the file $sourcedir/$destfile to $ARCHIVEVOL/$destfile.gz
# Parameters:	destfile	the destination filename 
#		sourcefile	the existing (source) file
#		sourcedir	the existing (source) directory
# filearc will not overwrite an existing destfile.
# filearc returns 1 if it successfully archived the file, 0 otherwise.

sub filearc {
	my ($destfile, $sourcefile, $sourcedir) = @_;
	$ARCHIVEVOL = "/home_";

	if ($destfile eq "") {
		printf( "filearc: $destfile not supplied.\n" );
		return 0;
	}
	if ($sourcefile eq "") {
		printf( "filearc: $sourcefile not supplied.\n" );
		return 0;
	}
	if (-e "/tmp/$destfile.gz") { unlink "/tmp/$destfile.gz"; }

	#
	# Make sure there is enough /tmp space
	#

	$avail = get_available_space( "/tmp" );
	if (((-s "$sourcedir/$sourcefile") / 1024) > $avail) {
		printf( "filearc: insufficient space on /tmp.\n" );
		return 0;
	}

	#
	# gzip the file into a temp file in /tmp
	#

	if (-d $sourcedir) {
		$script = "#!/bin/sh\n/usr/bin/gzip -c9 $sourcedir/$sourcefile >/tmp/$destfile.gz\n/usr/bin/chmod 600 /tmp/$destfile.gz\n";
		$res = runscript( $script );
		if ($res == 0) {
			printf( "filearc: gzip failed\n" );
			return 0;
		}
	}
	else {
		printf( "filearc: $sourcedir is not a directory.\n" );
		return 0;
	}

	#
	# Check that archive vol has space for the gzip'ed file.
	#

	$avail = get_available_space( $ARCHIVEVOL );
	if (((-s "/tmp/$destfile.gz") / 1024) > $avail) {
		printf( "filearc: insufficient space on $ARCHIVEVOL($avail) for $destfile (".((-s "/tmp/$destfile.gz") / 1024).").\n" );
		return 0;
	}

	#
	# Copy the file to the archive vol
	#

	if (!copyfile( "$destfile.gz", "/tmp", $ARCHIVEVOL, 0, 0 )) {
		printf( "filearc: copy of $destfile.gz from /tmp to $ARCHIVEVOL failed.\n" );
		return 0;
	}

	#
	# Check that the copied file is the same size
	#

	if (-e "$ARCHIVEVOL/$destfile.gz") {
		if ((-s "$ARCHIVEVOL/$destfile.gz") != (-s "/tmp/$destfile.gz")) {
			printf( "filearc: size inconsistency in copied file.\n");
			return 0;
		}
	}
	else {
		printf( "filearc: $ARCHIVEVOL/$destfile.gz disappeared!\n" );
		return 0;
	}

	unlink "/tmp/$destfile.gz";
		
	return 1;
}

sub backup_and_delete_directory {
	my ($dir, $name) = @_;
	if (!-d $BAKDIR) {
		if (!makedir( $BAKDIR, 0700, $REAL_USER_ID, $REAL_GROUP_ID )) { 
			printf( "Couldn't create $BAKDIR.\n" );
			return 0;
		}
	}
	$retcode = dirbak( "$BAKDIR/$name.tar", $dir );
	if ($retcode) {
		recursive_delete( $dir );
	}
	return $retcode;
}

# Get the "physical" volume on which the users home dir resides.

sub get_current_vol {
	my ($user) = @_;
	return readlink "/home/$user";
}

# Get the file system part of a path.
# eg. given the argument "/staff1/urquhart" this returns "/staff1"

sub get_filesys {
	my ($dir) = @_;
	@pathcomp = split /\//, $dir;
	return "/$pathcomp[1]";
}

# Get the available space on a volume

sub get_available_space {
	my ($dir) = @_;
	my ($line, $kbytes, $vol, $used,$avail,$junk);
	open DF,"/usr/bin/df -k $dir |";
	$line = <DF>; # skip the first line
	$line = <DF>;
	chomp $line;
	($vol,$kbytes,$used,$avail,$junk) = split /\s+/, $line;
	return $avail;
}


# Delete a directory.
# This uses a recursive algorithm that lists path if it is a directory,
# then deletes the files in the list, or calls recursive_delete if 
# it finds a sub-directory.
# Care is taken that any system files are not deleted by accident
# or maliciously. eg. by a user putting a link to "/" in their directory.
# Returns 1 if path was successfully deleted, 0 otherwise.

sub recursive_delete {
	my ($path) = @_;
	local (@files, $file);

	if (protected_file($path)) { return 0; }
        if (-l $path) {
           # it's a symbolic link - unlink it
           return unlink $path;
        } elsif (-d $path) {
		# It's a directory
		# Get a list of the files/sub-directories 
		# and call recursive_delete on each one.

		opendir PATH, $path;
		@files = grep !/^\.\.?$/, readdir PATH;
		closedir PATH;
		foreach $file (@files) {
			recursive_delete( "$path/$file" );
		}
		return rmdir $path;
	}
	else {
		# It's a file - delete it
		return unlink $path;
	}
}
	
# Run a script passed as a string

sub runscript {
	my ($script) = @_;

	$tmpname = "/tmp/scr$$";
	open SCRIPT, ">$tmpname";
	print SCRIPT $script;
	close SCRIPT;
	chmod 0700, $tmpname;
	@args = ($tmpname);
	$rc = 0xffff & system(@args);
	if ($rc != 0) { return 0; }
	return 1;
}

# Delete files associated with an account
# Parameter:	user	the userid 
# The files deleted are:
#	the home dir
#	the "/home/user" link
#	/var/mail/user
#	/var/popper/user
#	/gfs1/user (this may be separate from the home dir)
# Returns 1 if successful, or 0 if there was a problem. Note that
# it may return 1 even if the some files are not deleted.

sub delete_account_files {
	my ($user) = @_;

	if ($user eq "") {
		printf "delete_account_files: no user supplied.\n";
		return 0;
	}
	$path = get_current_vol( $user );
	if ($path eq "") {
		printf "delete_account_files: Couldn't get home dir for $user.\n";
		return 0;
	}
	
	if (!recursive_delete( $path )) {
		printf "delete_account_files: $path was not deleted.\n";
	}
	if (-l "/home/$user") { unlink "/home/$user"; }
        my $maildir = "/var/mail/".substr($user,0,1)."/".substr($user,1,1);
        if (-f "$maildir/$user") { unlink "$maildir/$user"; }
	if (-f "/var/popper/$user") { unlink "/var/popper/$user"; }
	if (-d "/gfs1/$user") { recursive_delete("/gfs1/$user"); }
	return 1;
}
	
# Delete archive files associated with an account
# Parameter:	user	the userid 

sub delete_archive_files {
	my ($user) = @_;
	
	if (-f "/home_/$user.home.tar.gz") { unlink "/home_/$user.home.tar.gz"; };
	if (-f "/home_/$user.mail.tar.gz") { unlink "/home_/$user.mail.tar.gz"; };
	if (-f "/home_/$user.csil.tar.gz") { unlink "/home_/$user.csil.tar.gz"; };
}

# Check to see if a path is a protected file or directory
# Parameters:	path	the path to be checked.

sub protected_file {
	my ($path) = @_;

	if ($path eq "/"
		|| $path eq "/external"
		|| $path eq "/faculty1"
		|| $path eq "/gfs1"
		|| $path eq "/grad1"
		|| $path eq "/home"
		|| $path eq "/staff1"
		|| $path eq "/staff2"
		|| $path eq "/tmp"
		|| $path eq "/ucs1"
		|| $path eq "/var"
		|| $path eq "/var/mail"
		|| $path eq "/ugrad1"
		|| $path eq "/ugrad2") { return 1; }
	if ($path =~ /^\/bin/
		|| $path =~ /^\/cdrom/
		|| $path =~ /^\/dev/
		|| $path =~ /^\/devices/
		|| $path =~ /^\/etc/
		|| $path =~ /^\/export/
		|| $path =~ /^\/kernel/
		|| $path =~ /^\/lib/
		|| $path =~ /^\/lost+found/
		|| $path =~ /^\/mnt/
		|| $path =~ /^\/net/
		|| $path =~ /^\/opt/
		|| $path =~ /^\/platform/
		|| $path =~ /^\/proc/
		|| $path =~ /^\/sbin/
		|| $path =~ /^\/usr/
		|| ($path =~ /^\/var/ && !($path =~ /^\/var\/mail/))
		|| $path =~ /^\/xfn/) { return 1; }
	return 0;
}

sub archiveuser {
        my ($user, $verbose) = @_;
        $archived = 0;
        $homedir = get_current_vol( $user );
        if (-d $homedir && dir_contains_non_excluded_files( $homedir )) {
                if (dirarc( "$user.home", $homedir )) {
                        cleanup_homedir( $user );
                        $archived++;
                }
				my $maildir = "/var/mail/".substr($user,0,1)."/".substr($user,1,1);
                if (-e $maildir && filearc( "$user.mail", "$user", $maildir )) {
                        recursive_delete( "/var/mail/$user" );
                }
                if (-e "/var/popper/$user" && filearc( "$user.pop", "$user", "/var/popper" )) {
                        recursive_delete( "/var/popper/$user" );
                }

                if (-d "/gfs1/CSIL/$user" && dirarc( "$user.csil", "/gfs1/CSIL/$user" )) {
                        recursive_delete( "/gfs1/CSIL/$user" );
                }
        }
	else {
		return 1;
	}
        return $archived;
}

sub cleanup_homedir {
        my ($user) = @_;
        my $homedir = get_current_vol( $user );
        my ($file, @files);
	my @excluded = get_excluded();

        if (-d $homedir) {
                opendir PATH, $homedir;
                @files = grep !/^\.\.?$/, readdir PATH;
                closedir PATH;
                foreach $file (@files) {
                        if ($file eq "." || $file eq ".." || isexcluded($file)) {
				next; 
			}
                        else {
				recursive_delete( "$homedir/$file" );
			}
                }
        }
        else {
                printf( "cleanup_homedir: $homedir is not a directory.\n" );
        }
}

sub dir_contains_non_excluded_files {
	my ($dir) = @_;
	my @excluded = get_excluded();
	local $pattern;

	#
	# Slurp the $dir file list into @files
	#
        opendir PATH, $dir;
        @files = grep !/^\.\.?$/, readdir PATH;
        closedir PATH;

	#
	# If any of the files are not in the excluded list, return true
	#
        foreach $file (@files) {
		$pattern = quotemeta $file;
		if (grep /^$pattern$/, @excluded) { next; }
		return 1;
	}

	return 0;
}
	
sub isexcluded {
	my ($file) = @_;
	my $pattern = quotemeta $file;
	local @excluded = get_excluded();
	return grep /^$pattern$/, @excluded;
}

sub get_excluded {
	my @excluded; 
	#
	# Slurp the EXCLUDED file list into @excluded
	#
	open EXCLUDED or die "Can't find $EXCLUDED: $!\n";
	@excluded = <EXCLUDED>;
	chomp @excluded;
	return @excluded;
}

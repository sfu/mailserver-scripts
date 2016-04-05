package Aliases;

use DB_File;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( aliasToUsername isStaticAlias validUser );

#
# return the equivalent username of a supplied alias,
# or undefined if it is not a non-static alias.
#
sub aliasToUsername {
	my $alias = shift;
	return undef if isStaticAlias($alias);
 	tie %ALIASES, "DB_File","/opt/mail/aliases.db", O_RDONLY, 0666
		or die "Can't open /opt/mail/aliases: $!\n";
	my $username = $ALIASES{"$alias\0"};
	if ($username) {
 		untie %ALIASES;
		chop $username;
		$username =~ s/^\s+//;
		$username =~ s/\s+$//;
		return $username;
	}
	# might be a dotted form of alias
	$alias =~ tr/./_/;
	$username = $ALIASES{"$alias\0"};
 	untie %ALIASES;
	chop $username if $username;
	$username =~ s/^\s+//;
	$username =~ s/\s+$//;
	return $username;
}

sub isStaticAlias {
	my $addr = lc shift;
	&loadStaticAliases unless defined($main::StaticAliases);
	return defined($main::StaticAliases->{$addr});
}

sub loadStaticAliases {
	my $sa = {};
	unless (open( STATIC, "</opt/mail/staticaliases" )) {
		print STDERR "Can't open static aliases: $!\n";
		return 0;
	}
	while (<STATIC>) {
		chomp;
		($alias, $target) = split /:/;
		$target =~ s/^\s+//;
		$sa->{lc $alias} = $target;
	}
	close STATIC;
	$main::StaticAliases = $sa;
}

# Returns user if user exists in secondary Aliases map (which
# contains all users in passwd map)

sub validUser {
	my $user = shift;
	tie %ALIASES, "DB_File", "/opt/mail/aliases2.db", O_RDONLY, 0666
		or die "Can't open /opt/mail/aliases2.db: $!\n";
	if (defined($ALIASES{"$user\0"})) {
		untie %ALIASES;
		return $user;
	}
	untie %ALIASES;
	return undef;
}


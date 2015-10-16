package Aliases;

require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( aliasToUsername isStaticAlias );

#
# return the equivalent username of a supplied alias,
# or undefined if it is not a non-static alias.
#
sub aliasToUsername {
	my $alias = shift;
	return undef if isStaticAlias($alias);
	dbmopen %ALIASES, "/opt/mail/aliases", 0666
		or die "Can't open /opt/mail/aliases: $!\n";
	my $username = $ALIASES{"$alias\0"};
	if ($username) {
		dbmclose %ALIASES;
		chop $username;
		$username =~ s/^\s+//;
		$username =~ s/\s+$//;
		return $username;
	}
	# might be a dotted form of alias
	$alias =~ tr/./_/;
	$username = $ALIASES{"$alias\0"};
	dbmclose %ALIASES;
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


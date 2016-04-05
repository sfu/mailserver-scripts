#!/usr/bin/perl
open LDAP, '/usr/bin/ldapsearch -x -H ldap://bentley1.tier2.sfu.ca:389 "(&(objectClass=zimbraAccount)(zimbraPrefMailForwardingAddress=*))" zimbraPrefMailForwardingAddress|' or die "Open pipe from ldapsearch failed: $!\n";
open ZIMBRA, '>/opt/mail/zimbraforwards' or die "Open /opt/mail/zimbraforwards failed: $!\n";
$skip = 0;
while (<LDAP>) {
    chomp;
    next if /^#/;
    next unless $_;
    next if /^search:/;
    next if /^result:/;
    if (/^dn: uid=(\w+),ou=people,dc=sfu,dc=ca$/) {
        $uid = $1;
	$skip = 0;
    }
    elsif (/^dn: uid=/) {
	$skip = 1;
	next;
    }
    if (!$skip && /^zimbraPrefMailForwardingAddress: (\S+)$/) {
        @forwards = split(/[,;]/,$1);
	foreach $forward (@forwards) {
            print ZIMBRA "$uid:$forward\n";
	}
    }
}

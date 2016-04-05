#!/usr/local/bin/perl
use lib '/usr/local/amaint/prod/lib';
use Amaintr;

#
# THis token contains a wildcard ip
#
$main::TOKEN = '3w2SzeyZ5JfWQBnKsJ.3lNsOVU1XsTuFv8t0.YdTUvPuUl6df3e6Ig';
#

$main::TEST = 1;

my $amaintr = new Amaintr($main::TOKEN, $main::TEST);

$accounts = $amaintr->getExpireList('active');
print $accounts;

exit 0;
$accounts = $amaintr->getUsernamesWithStatus('pending create');
foreach $account (@$accounts) {
  print "$account\n";
}

$hashref = $amaintr->getAttributes('robert');
foreach $key (keys %$hashref) {
#   print "$key: ".$hashref->{$key}."\n";
}

#print $amaintr->getPW();

#print $amaintr->getStaticAliases();

#print $amaintr->getAliases();

#print $amaintr->getNetgroup();

#print $amaintr->defaultFileQuota();
print "\n";

#print $amaintr->getQuotas();

#print $amaintr->getMigrateInfo();

#print $amaintr->unsetMigrateFlag('kipling');

#print $amaintr->getMigrateInfo();


exit 0;
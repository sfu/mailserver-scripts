package Amaintr;
use lib '/usr/local/amaint/prod/lib';
use HTTPMethods;
use Utils;
require Exporter;
@ISA    = qw(Exporter);

#
# Service url for testing
#
use constant URLBASETST => "https://stage.its.sfu.ca/cgi-bin/WebObjects/Amaint.woa/wa/";

#
# Service url for prod
#
use constant URLBASE => "https://amaint.sfu.ca/cgi-bin/WebObjects/AmaintRest.woa/wa/";

use constant TXT => 1;

sub new {
	my $class = shift;
	my $token = shift;
	my $isTest = shift;
	my $self = {};
	bless $self, $class;
	$self->{token} = $token;
	$self->{isTest} = $isTest;
	$self->{isProd} = !$isTest;
	$self->{baseUrl} = URLBASETST;
	$self->{baseUrl} = URLBASE if $self->{isProd};
	_stdout("baseUrl is ".$self->{baseUrl}) if $self->{isTest};
	return $self;
}

sub defaultFileQuota {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "defaultFileQuota?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub destroyAccount {
	my $self = shift;
    my $username = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($username) {
        return 'err No username supplied';
    }
    
    my $url = $self->{baseUrl} . "destroyAccount?username=$username&token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub expireAccount {
	my $self = shift;
    my $username = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($username) {
        return 'err No username supplied';
    }
    
    my $url = $self->{baseUrl} . "expireAccount?username=$username&token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub flagAccountsToBeDestroyed {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "flagAccountsToBeDestroyed?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getExpireList {
	my $self = shift;
    my $status = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($status) {
        return 'err No status supplied';
    }
    
    my $url = $self->{baseUrl} . "getExpireList?status=$status&token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getUsernamesWithStatus {
	my $self = shift;
    my $status = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($status) {
        return 'err No status supplied';
    }

    my $url = $self->{baseUrl} . "getUsernamesWithStatus?status=$status&token=" . $self->{token};
	my $result = _httpGet($url, TXT);
    my @data = split /\n/,$result;
    return \@data;
}

sub getAliases {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getAliases?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getStaticAliases {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getStaticAliases?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getAttributes {
	my $self = shift;
    my $username = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($username) {
        return 'err No username supplied';
    }

    my $url = $self->{baseUrl} . "getAttributes?username=$username&token=" . $self->{token};
	my $ref = _httpGet($url, !TXT);
    return $ref;
}

sub getAccountMigrateInfo {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getAccountMigrateInfo?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getNetgroup {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getNetgroupInfo?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getPW {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getPW?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub getQuotaInfo {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "getQuotaInfo?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub homeDirCreated {
	my $self = shift;
    my $username = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($username) {
        return 'err No username supplied';
    }
    
    my $url = $self->{baseUrl} . "homeDirCreated?username=$username&token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub fireImport {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    
    my $url = "https://amaint.sfu.ca/cgi-bin/WebObjects/Amaint.woa/wa/fireImport?token=" . $self->{token};
    return _httpGet($url, TXT);
}

sub fireWarnings {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    
    my $url = $self->{baseUrl} . "fireWarnings?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub lightweightMap {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }

    my $url = $self->{baseUrl} . "lightweightMap?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub runPSQueue {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    
    my $url = $self->{baseUrl} . "runPSQueue?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub timeoutAccountOverrides {
	my $self = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    
    my $url = $self->{baseUrl} . "timeoutAccountOverrides?token=" . $self->{token};
	return _httpGet($url, TXT);
}

sub unsetMigrateFlag {
	my $self = shift;
    my $username = shift;

    unless ($self->{token}) {
        _stderr("No token");
        return '';
    }
    unless ($username) {
        return 'err No username supplied';
    }
    
    my $url = $self->{baseUrl} . "unsetMigrateFlag?username=$username&token=" . $self->{token};
	return _httpGet($url, TXT);
}


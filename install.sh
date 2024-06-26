#!/bin/sh
##
## Install required perl libs
##

export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

umask 022

. /etc/profile.d/proxy.sh

# Install dependencies and whatever perl modules we can via Yum
dnf install -y gcc perl-CPAN perl-CPAN-Meta perl-libwww-perl perl-XML-LibXML perl-XML-Simple perl-MailTools \
           perl-JSON perl-Sys-Syslog perl-DB_File perl-LWP-Protocol-https perl-IO-Zlib

# Precreate CPAN config
#
mkdir -p /root/.cpan/CPAN

if [ ! -e /root/.cpan/CPAN/MyConfig.pm ]; then
    cat > /root/.cpan/CPAN/MyConfig.pm <<EOF

\$CPAN::Config = {
  'applypatch' => q[],
  'auto_commit' => q[0],
  'build_cache' => q[100],
  'build_dir' => q[/root/.cpan/build],
  'build_dir_reuse' => q[0],
  'build_requires_install_policy' => q[yes],
  'bzip2' => q[],
  'cache_metadata' => q[1],
  'check_sigs' => q[0],
  'commandnumber_in_prompt' => q[1],
  'connect_to_internet_ok' => q[1],
  'cpan_home' => q[/root/.cpan],
  'ftp_passive' => q[1],
  'ftp_proxy' => q[http://proxy.sfu.ca:8080],
  'getcwd' => q[cwd],
  'gpg' => q[/usr/bin/gpg],
  'gzip' => q[/usr/bin/gzip],
  'halt_on_failure' => q[0],
  'histfile' => q[/root/.cpan/histfile],
  'histsize' => q[100],
  'http_proxy' => q[http://proxy.sfu.ca:8080],
  'inactivity_timeout' => q[0],
  'index_expire' => q[1],
  'inhibit_startup_message' => q[0],
  'keep_source_where' => q[/root/.cpan/sources],
  'load_module_verbosity' => q[none],
  'make' => q[/usr/bin/make],
  'make_arg' => q[],
  'make_install_arg' => q[],
  'make_install_make_command' => q[sudo /usr/bin/make],
  'makepl_arg' => q[],
  'mbuild_arg' => q[],
  'mbuild_install_arg' => q[],
  'mbuild_install_build_command' => q[sudo ./Build],
  'mbuildpl_arg' => q[],
  'no_proxy' => q[],
  'pager' => q[/usr/bin/less],
  'patch' => q[],
  'perl5lib_verbosity' => q[none],
  'prefer_external_tar' => q[1],
  'prefer_installer' => q[MB],
  'prefs_dir' => q[/root/.cpan/prefs],
  'prerequisites_policy' => q[follow],
  'proxy_user' => q[],
  'scan_cache' => q[atstart],
  'shell' => q[/bin/bash],
  'show_unparsable_versions' => q[0],
  'show_upload_date' => q[0],
  'show_zero_versions' => q[0],
  'tar' => q[/usr/bin/tar],
  'tar_verbosity' => q[none],
  'term_is_latin' => q[1],
  'term_ornaments' => q[1],
  'test_report' => q[0],
  'trust_test_report_history' => q[0],
  'unzip' => q[/usr/bin/unzip],
  'urllist' => [q[http://mirror.csclub.uwaterloo.ca/CPAN/], q[http://mirror.its.dal.ca/cpan/], q[http://cpan.metacpan.org/]],
  'use_sqlite' => q[0],
  'version_timeout' => q[15],
  'wget' => q[/usr/bin/wget],
  'yaml_load_code' => q[0],
  'yaml_module' => q[YAML],
};
1;
__END__
EOF

fi

# Install required perl modules that aren't available via Yum

perl -MCPAN -e 'install Test::Fatal'
perl -MCPAN -e 'install Test::Deep'
perl -MCPAN -e 'install Net::Stomp'
perl -MCPAN -e 'install XML::Generator'
perl -MCPAN -e 'install Module::Build::Tiny'
perl -MCPAN -e 'install Net::Statsd::Client'
perl -MCPAN -e 'install Text::CSV::Hashify'

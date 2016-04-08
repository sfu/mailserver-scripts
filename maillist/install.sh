#!/bin/sh
#
# Create directories (if they don't exist) and install required perl libs
export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

perl -MCPAN -e 'install JSON'
perl -MCPAN -e 'install Net::Statsd::Client'
#
# Need to edit mlq.pl and mlproxy.pl and insert path to libs, or figure out how to calculate it
#
# Place symlinks to mlq.pl and mlproxy.pl in /etc/smrsh

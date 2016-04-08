#!/bin/sh
#
# Create directories (if they don't exist) and install required perl libs
export PERL_MM_USE_DEFAULT=1
export PERL_EXTUTILS_AUTOINSTALL="--defaultdeps"

perl -MCPAN -e 'install Net::Stomp'
perl -MCPAN -e 'install XML::LibXML'
#
# Need to create blockfile in /opt/mail. Must contain 'alumhelp' on mailgw1/2 and several users on pobox1/2

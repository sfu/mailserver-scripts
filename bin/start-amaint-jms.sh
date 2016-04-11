#!/bin/sh
#
# Simple script to start amaint-jms
# This script will restart amaint-jms if it dies, and log why it died.

while true
do
        if [ -x /opt/amaint/prod/bin/amaint-jms.pl ]; then
		sleep 30
                /opt/amaint/prod/bin/amaint-jms.pl >> /tmp/amaint-jms.log
                # We only reach here if it dies
                echo "amaint-jms died with error code: $? at \c"
                date
        fi
done

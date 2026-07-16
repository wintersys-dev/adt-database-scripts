#!/bin/sh

/bin/touch  /var/lib/aptitude/pkgstates

while ( [ "`/usr/bin/fuser /var/lib/dpkg/lock-frontend`" != "" ] )
do
        echo "Waiting for another package manager process to complete..."
        sleep 5
done

/usr/bin/aptitude "$@"

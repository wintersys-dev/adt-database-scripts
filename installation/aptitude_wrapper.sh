#!/bin/sh

if ( [ ! -f  /var/lib/aptitude/pkgstates ] )
then
        /bin/touch  /var/lib/aptitude/pkgstates
fi

while ( [ "`/usr/bin/fuser /var/lib/dpkg/lock-frontend`" != "" ] )
do
        echo "Waiting for another package manager process to complete..."
        sleep 5
done

/usr/bin/aptitude "$@"

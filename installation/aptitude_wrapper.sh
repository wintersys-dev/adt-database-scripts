#!/bin/sh

set -x

while ( [ "`/usr/bin/fuser /var/lib/dpkg/lock-frontend`" != "" ] )
do
        echo "Waiting for another package manager process to complete..."
        sleep 5
done

/usr/bin/dpkg --configure -a
command="/usr/bin/aptitude $@"

success="0"
count="0"

while ( [ "${success}" = "0" ] && [ "${count}" -lt "30" ] )
do
        eval "${command}"
        if ( [ "$?" = "0" ] )
        then    
                success="1"
        else
                count="`/usr/bin/expr ${count} + 1`"
                /bin/sleep 5
        fi
done

if ( [ "${count}" = "30" ] )
then
        /bin/echo "command: ${command} failed"
fi

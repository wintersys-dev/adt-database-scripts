if ( [ -f ${HOME}/runtime/EMERGENCY_RESTORATION_IN_PROGRESS ] )
then
        exit
fi

marker="`${HOME}/services/datastore/operations/ListFromDatastore.sh "config" "ACTIVATE_RESTORATION" | /bin/grep -o "ACTIVATE_RESTORATION.*"`"

if ( [ "${marker}" != "" ] )
then
        /bin/touch ${HOME}/runtime/EMERGENCY_RESTORATION_IN_PROGRESS
        ${HOME}/application/backup/EmergencyRestoration.sh
else
        exit
fi

/bin/sleep 120

if ( [ -f ${HOME}/application/backup/EmergencyRestoration.sh ] )
then
        /bin/rm ${HOME}/runtime/EMERGENCY_RESTORATION_IN_PROGRESS
fi


if ( [ "${marker}" != "" ] )
then
        ${HOME}/services/datastore/operations/DeleteFromDatastore.sh "config" "${marker}" "local"
fi

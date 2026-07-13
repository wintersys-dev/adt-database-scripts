#!/bin/sh
#set -x

HOME="`/bin/cat /home/homedir.dat`"
archive_id="`${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "ACTIVATE_RESTORATION.ARCHIVE" | /bin/sed 's/ACTIVATE_RESTORATION\.//g'`"
archive_id="`/bin/echo ${archive_id} | /usr/bin/tr '[:upper:]' '[:lower:]'`"

if ( [ "${archive_id}" = "" ] )
then
        exit
fi

if ( [ ! -d ${HOME}/runtime/restoration_archives ] )
then
        /bin/mkdir -p ${HOME}/runtime/restoration_archives
fi

#${HOME}/services/database/BackupDatabase.sh "${HOME}/runtime/restoration_archives/restoration_db.tar.gz"
#/bin/tar xvfz ${HOME}/runtime/restoration_archives/restoration_db.tar.gz -C ${HOME}/runtime/restoration_archives

/bin/echo ${archive_id} > ${HOME}/runtime/restoration_archives/ARCHIVE_ID

${HOME}/services/database/InitialiseDatabase.sh
DB_N="`${HOME}/utilities/config/ExtractConfigValue.sh 'DBNAME' | /bin/sed 's/_archive.*//g'`"
DB_N1="`/bin/echo .${archive_id} | /bin/sed -e 's/\./_/g' -e 's/-/_/g'`"
DB_N2="`${HOME}/utilities/config/ExtractConfigValue.sh 'DBNAME'`"
/bin/grep -rlZ ${DB_N2} ${HOME}/runtime | /usr/bin/xargs -0 /bin/sed -i "s/${DB_N2}/${DB_N}${DB_N1}/g"
${HOME}/application/db/InstallApplicationDB.sh "${archive_id}"

/bin/rm ${HOME}/runtime/restoration_archives/ARCHIVE_ID


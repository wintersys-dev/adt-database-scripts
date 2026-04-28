#!/bin/sh
###########################################################################################################
# Description: This script will perform a backup of the database when it is called from cron
# It is called at set periods from cron and if you want to call it manually you can look in the 
# directory ${BUILD_HOME}/helperscripts relating to making backups and baselines for how to backup
# your database manually.
# Look there for further explaination
# Date: 16/11/2016
# Author: Peter Winter
###########################################################################################################
# License Agreement:
# This file is part of The Agile Deployment Toolkit.
# The Agile Deployment Toolkit is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# The Agile Deployment Toolkit is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with The Agile Deployment Toolkit.  If not, see <http://www.gnu.org/licenses/>.
####################################################################################
####################################################################################
#set -x

periodicity="${1}"

MULTI_REGION="`${HOME}/utilities/config/ExtractConfigValue.sh 'MULTIREGION'`"

if ( [ "${MULTI_REGION}" = "1" ] )
then
	if ( [ -f ${HOME}/runtime/datastore_workarea/time_backup_written ] )
	then
        /bin/rm ${HOME}/runtime/datastore_workarea/time_backup_written
	fi

	if ( [ ! -d ${HOME}/runtime/datastore_workarea ] )
	then
		/bin/mkdir -p ${HOME}/runtime/datastore_workarea
	fi

	${HOME}/services/datastore/operations/GetFromDatastore.sh "backup" "time_backup_written" "${HOME}/runtime/datastore_workarea" "${periodicity}"

	if ( [ -f ${HOME}/runtime/datastore_workarea/time_backup_written ] )
	then
        current_time="`/usr/bin/date +%s`"
        backup_time="`/bin/cat ${HOME}/runtime/datastore_workarea/time_backup_written`"
        if ( [ "`/usr/bin/expr ${current_time} - ${backup_time}`" -lt "300" ] )
        then
                exit
        fi
	fi

	/bin/sleep "`/usr/bin/shuf -i1-300 -n1`"

	if ( [ "`${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "DB_BACKUP_RUNNING"`" != "" ] )
	then
		if ( [ "`${HOME}/services/datastore/config/wrapper/AgeOfDatastoreFile.sh "config" "DB_BACKUP_RUNNING"`" -gt "300" ] )
		then
			${HOME}/services/datastore/config/wrapper/DeleteFromDatastore.sh "config" "DB_BACKUP_RUNNING"
		fi
	fi

	/bin/sleep "`/usr/bin/shuf -i1-60 -n1`"

	if ( [ "`${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "DB_BACKUP_RUNNING"`" != "" ] )
	then
		exit
	else
		${HOME}/services/datastore/config/wrapper/PutToDatastore.sh "config" "DB_BACKUP_RUNNING" "root" "yes"
	fi
fi

${HOME}/application/backup/Backup.sh "${periodicity}"

if ( [ "${MULTI_REGION}" = "1" ] )
then
	/bin/sleep 300
	${HOME}/services/datastore/config/wrapper/DeleteFromDatastore.sh "config" "DB_BACKUP_RUNNING"
fi

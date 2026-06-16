#!/bin/sh
###################################################################################
# Description: This  will install postgres server
# Date: 18/11/2016
# Author : Peter Winter
###################################################################################
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

if ( [ "${1}" != "" ] )
then
	buildos="${1}"
fi

if ( [ "${buildos}" = "" ] )
then
	BUILDOS="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDOS'`"
else 
	BUILDOS="${buildos}"
fi

apt=""
if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt" ] )
then
	apt="/usr/bin/apt"
elif ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt-get" ] )
then
	apt="/usr/bin/apt-get"
fi

export DEBIAN_FRONTEND=noninteractive
install_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y install " 
update_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y update " 

count="0"
while ( [ ! -f /usr/bin/psql ] && [ "${count}" -lt "5" ] )
do
	if ( [ "${apt}" != "" ] )
	then
		if ( [ "${BUILDOS}" = "ubuntu" ] )
		then  
			if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "POSTGRES" | /usr/bin/awk -F':' '{print $NF}'`" != "cloud-init" ] )
			then
				postgres_version="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "POSTGRES" | /usr/bin/awk -F':' '{print $NF}'`"
				
				if ( [ "${postgres_version}" = "default" ] )
				then
					${update_command}
					${install_command} postgresql-client
				else
					${install_command} postgresql-common
					/bin/echo "yes" | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
					${install_command} curl ca-certificates
					/usr/bin/install -d /usr/share/postgresql-common/pgdg
					/usr/bin/curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
					. /etc/os-release
					${update_command}
					${install_command} postgresql-client-${postgres_version}
				fi
			fi
			${HOME}/utilities/processing/RunServiceCommand.sh postgresql restart                                                   
		fi

		if ( [ "${BUILDOS}" = "debian" ] && [ ! -f /usr/lib/postgresql ] )
		then  
			if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "POSTGRES" | /usr/bin/awk -F':' '{print $NF}'`" != "cloud-init" ] )
			then
				postgres_version="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "POSTGRES" | /usr/bin/awk -F':' '{print $NF}'`"

				if ( [ "${postgres_version}" = "default" ] )
				then
					${update_command}
					${install_command} postgresql-client
				else
					${install_command} postgresql-common
					/usr/bin/yes | /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
					${install_command} curl ca-certificates
					/usr/bin/install -d /usr/share/postgresql-common/pgdg
					/usr/bin/curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
					. /etc/os-release
					${update_command}
					${install_command} postgresql-client-${postgres_version}
				fi
			fi
			${HOME}/utilities/processing/RunServiceCommand.sh postgresql restart
		fi
	fi
	count="`/usr/bin/expr ${count} + 1`"
done

if ( [ ! -x /usr/bin/psql ] && [ "${count}" = "5" ] )
then
	${HOME}/services/email/SendEmail.sh "INSTALLATION ERROR POSTGRES" "I believe that postgres client hasn't installed correctly, please investigate" "ERROR"
else
	/bin/touch ${HOME}/runtime/installedsoftware/InstallPostgresClient.sh
fi


#!/bin/sh
###################################################################################
# Description: This  will install mariadb server. I considered it to be too lengthy a process
# to build mariadb from source, build time wise, so, only the repo option is supported.
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
set -x

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

BUILDOS="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDOS'`"
BUILDOS_VERSION="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDOSVERSION'`"

apt=""
if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt" ] )
then
        apt="/usr/bin/apt"
elif ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt-get" ] )
then
        apt="/usr/bin/apt-get"
fi

export DEBIAN_FRONTEND=noninteractive
update_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y update "
install_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y install " 
purge_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y purge " 
auto_remove_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y autoremove " 
auto_clean_command="${apt} -o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y autoclean " 

count="0"
while ( [ ! -f /usr/bin/mariadbd-safe ] && [ "${count}" -lt "5" ] )
do
	if ( [ "${apt}" != "" ] )
	then
        if ( [ "${BUILDOS}" = "ubuntu" ] )
        then
        	if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "MARIADB" | /usr/bin/awk -F':' '{print $NF}'`" != "cloud-init" ] )
        	then
    			mariadb_version="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "MARIADB" | /usr/bin/awk -F':' '{print $NF}'`"
    			if ( [ "${mariadb_version}" = "default" ] )
        		then
				#	${install_command} mariadb-server
				:
				else
    				if ( [ "${BUILDOS_VERSION}" = "24.04" ] )
    				then
    					os_type="ubuntu" 
						os_version="noble"
					fi
					if ( [ "${BUILDOS_VERSION}" = "26.04" ] )
					then
						os_type="ubuntu" 
						os_version="resolute"
					fi
					#At the time of writing this script doesn't support Ubuntu 26.04 so the default for the OS will have to be used
					#until such time as the script supports it and then you should be all set to use non default versions on 26.04
					/usr/bin/curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-${mariadb_version}" --os-type="${os_type}" --os-version="${os_version}" --arch='amd64' --skip-maxscale
					${install_command} mariadb-server
				fi  
            fi
        fi

        if ( [ "${BUILDOS}" = "debian" ] )
        then
    		if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "MARIADB" | /usr/bin/awk -F':' '{print $NF}'`" != "cloud-init" ] )
        	then
            	mariadb_version="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "MARIADB" | /usr/bin/awk -F':' '{print $NF}'`"
				if ( [ "${mariadb_version}" = "default" ] )
				then
					${install_command} mariadb-server
				else
					if ( [ "${BUILDOS_VERSION}" = "26.04" ] )
					then
						os_type="debian"
						os_version="trixie"
					fi
					/usr/bin/curl -LsS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version="mariadb-${mariadb_version}" --os-type="${os)type}" --os-version="${os_version}" --arch='amd64' --skip-maxscale
					${install_command} mariadb-server
				fi
            fi
        fi
	fi
	
	if ( [ ! -d /var/log/mysql ] )
	then
		/bin/mkdir /var/log/mysql
		/bin/chown mysql:mysql /var/log/mysql                         
	fi
	
	${HOME}/utilities/processing/RunServiceCommand.sh mariadb enable
	${HOME}/utilities/processing/RunServiceCommand.sh mariadb restart
	
	count="`/usr/bin/expr ${count} + 1`"
done

if ( [ ! -f /usr/bin/mariadbd-safe ] && [ "${count}" = "5" ] )
then
        ${HOME}/services/email/SendEmail.sh "INSTALLATION ERROR MARIADB" "I believe that mariadb server hasn't installed correctly, please investigate" "ERROR"
else
        /bin/touch ${HOME}/runtime/installedsoftware/InstallMariaDBServer.sh
fi





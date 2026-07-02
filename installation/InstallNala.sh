#!/bin/sh
######################################################################################################
# Description: This script will install nala
# Author: Peter Winter
# Date: 17/01/2017
#######################################################################################################
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
#######################################################################################################
#######################################################################################################

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
HOME="`/bin/cat /home/homedir.dat`"

manager=""
if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "nala" ] )
then
	manager="/usr/bin/apt-get"
	options="-o DPkg::Lock::Timeout=-1 -o Dpkg::Use-Pty=0 -qq -y"
fi

export DEBIAN_FRONTEND=noninteractive
install_command="${manager} ${options} install"

count="0"
while ( [ ! -f /usr/bin/bzip2 ] && [ "${count}" -lt "5" ] )
do
	if ( [ "${manager}" != "" ] )
	then
		if ( [ "${BUILDOS}" = "ubuntu" ] )
		then
			eval ${install_command} nala
		fi

		if ( [ "${BUILDOS}" = "debian" ] )
		then
			eval ${install_command} nala
		fi
	fi
	count="`/usr/bin/expr ${count} + 1`"
done


if ( [ ! -x /usr/bin/nala ] && [ "${count}" = "5" ] )
then
	${HOME}/services/email/SendEmail.sh "INSTALLATION ERROR nala" "I believe that nala hasn't installed correctly, please investigate" "ERROR"
else
	/bin/touch ${HOME}/runtime/installedsoftware/InstallNala.sh	
fi

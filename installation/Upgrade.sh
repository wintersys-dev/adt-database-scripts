#!/bin/sh
###################################################################################
# Description: This  will perform a software upgrade
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

manager=""
options=""
tail_options=""
if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt" ] )
then
	manager="/usr/bin/apt"
	options="-o DPkg::Lock::Timeout=60 -qq -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -y --allow-downgrades --allow-remove-essential --allow-change-held-packages"
elif ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "apt-get" ] )
then
	manager="/usr/bin/apt-get"
	options="-o DPkg::Lock::Timeout=60 -qq -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef -y --allow-downgrades --allow-remove-essential --allow-change-held-packages"
elif ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "PACKAGEMANAGER" | /usr/bin/awk -F':' '{print $NF}'`" = "nala" ] )
then
	manager="/usr/bin/nala"
	tail_options="-y"
fi

if ( [ "${manager}" != "" ] )
then
	if ( [ "${BUILDOS}" = "ubuntu" ] )
	then
		${HOME}/installation/RemoveUnattendedUpgrades.sh "ubuntu"
		DEBIAN_FRONTEND=noninteractive ${manager} ${options} upgrade ${tail_options}
	fi

	if ( [ "${BUILDOS}" = "debian" ] )
	then
		DEBIAN_FRONTEND=noninteractive ${manager} ${options} upgrade ${tail_options}
	fi
fi

SERVER_USER="`/bin/ls -d /home/X*X | /usr/bin/awk -F'/' '{print $NF}'`"
/bin/chown -R ${SERVER_USER}:root ${HOME}
/bin/chmod 750 ${HOME}/utilities/security/EnforcePermissions.sh
${HOME}/utilities/security/EnforcePermissions.sh

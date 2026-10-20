#!/bin/sh
################################################################################
# Description: This script is using for sending emails based on whatever email utility
# is configured for use in software.dat
# Date: 16-11-2016
# Author: Peter Winter
##################################################################################
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
#####################################################################################
#####################################################################################
#set -x
set -e

HOME="`/bin/cat /home/homedir.dat`"

if ( [ "${1}" = "" ] || [ "${2}" = "" ] || [ "${3}" = "" ] )
then
        status "Error: Minimum of 3 arguments required."
        status "Usage: $0 <subject> <message> <level>"
        exit 1
fi

subject="$1"
message="$2"
level="$3"
to_address="$4"
content_type="$5"

if ( [ "${level}" = "ERROR" ] || [ "${level}" = "INFO" ] || [ "${level}" = "MANDATORY" ] )
then
        ip_address="`${HOME}/utilities/processing/GetPublicIP.sh`"
        message="MESSAGE RELATED TO MACHINE WITH IP ADDRESS: ${ip_address}: ${message}"
fi

email_util="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "EMAILUTIL" | /usr/bin/awk -F':' '{print $NF}'`"

if ( [ "${level}" != "MANDATORY" ] && [ "`${HOME}/utilities/config/CheckConfigValue.sh EMAILNOTIFICATIONLEVEL:ERROR`" = "1" ] && [ "${level}" != "ERROR" ] )
then
        exit
fi

if ( [ "${to_address}" = "" ] )
then
        to_address="system"
fi

if ( [ "${content_type}" = "" ] )
then
        content_type="default"
fi

${HOME}/services/email/${email_util}/SendEmail.sh "${subject}" "${message}" "${to_address}" "${content_type}"

if ( [ "$?" != "0" ] )
then
        /bin/echo "SendEmail.sh failed to send email"
        exit 1
fi

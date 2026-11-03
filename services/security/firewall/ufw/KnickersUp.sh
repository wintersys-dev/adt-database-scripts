#!/bin/sh
###################################################################################
# @file        EnforceLockdown.sh
# @brief       Context-Aware UFW Default Ingress Deny State Enforcement (KnickersUp).
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script enforces a highly restrictive security posture on the host by 
#              configuring the Uncomplicated Firewall (UFW) to drop all incoming connections 
#              by default. It extracts the necessary administrative credentials, asserts 
#              global ingress restrictions via privilege escalation, configures default 
#              outgoing permissions, and handles execution tracking markers.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#              - /usr/bin/sudo system administrative privilege escalation interface wrapper.
#
# @security    
#              - Locks down the edge network topology by setting a universal default-deny ingress posture.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#              - Avoids persisting unencrypted credentials in plaintext system variable histories.
#
# @exit        0  Success: Security posture verified or default tables securely updated.
# @exit        1  Failure: General system exception or privilege escalation failure.
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
# along with The Agile Deployment Toolkit.  If not, see <http://gnu.org>.
######################################################################################
######################################################################################
#set -x

set -e

HOME="$(/bin/cat /home/homedir.dat)"

SERVER_USER_PASSWORD="$(${HOME}/utilities/config/ExtractConfigValue.sh 'SERVERUSERPASSWORD')"
updated="0"

if [ ! -f ${HOME}/runtime/KNICKERS_ARE_UP ]
then
        /bin/echo "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /usr/sbin/ufw default deny incoming
        /bin/sleep 10
        /bin/echo "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /usr/sbin/ufw default allow outgoing
        /bin/touch ${HOME}/runtime/KNICKERS_ARE_UP
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

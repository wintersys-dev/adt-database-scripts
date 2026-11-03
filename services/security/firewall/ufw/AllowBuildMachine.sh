#!/bin/sh
###################################################################################
# @file        AllowBuildMachine.sh
# @brief       Context-Aware UFW Firewall Provisioning for Build Machine Access.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script manages host firewall rules for the centralized build platform
#              using the Uncomplicated Firewall (UFW) engine. It conditionally whitelists
#              incoming traffic from the designated build machine IP address targeting
#              defined SSH and secure web transport (443) infrastructure ports.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - CheckConfigValue.sh boolean validation mechanism verifying network targets.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#
# @security    
#              - Restricts build environment access strictly to single /32 IP bounds.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Firewall state verified; no new access modifications applied.
# @exit        10 Success: Active network routing tables updated with new firewall rules.
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

BUILD_MACHINE_IP="$(${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDMACHINEIP')"
SSH_PORT="$(${HOME}/utilities/config/ExtractConfigValue.sh 'SSHPORT')"

updated="0"

if [ "$(${HOME}/utilities/config/CheckConfigValue.sh BUILDMACHINEVPC:0)" = "1" ]
then
        if [ "$(/usr/sbin/ufw status | /bin/grep "${SSH_PORT}.*ALLOW.*${BUILD_MACHINE_IP}")" = "" ]
        then
                /usr/sbin/ufw allow from ${BUILD_MACHINE_IP}/32 to any port ${SSH_PORT}
                /usr/sbin/ufw allow from ${BUILD_MACHINE_IP}/32 to any port 443
                /bin/sleep 2
                updated="1"
        fi
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

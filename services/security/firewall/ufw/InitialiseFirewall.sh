#!/bin/sh
###################################################################################
# @file        InitialiseFirewall.sh
# @brief       Context-Aware UFW Firewall Factory Reset & State Initialisation Utility.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script securely handles state validation and factory clear operations
#              on the host Uncomplicated Firewall (UFW) layer. If an architecture node has
#              not been initialised and is not tracking an active profile state, the engine
#              resets all tables, purges the default TCP 22/SSH fallback rule, deactivates
#              logging, sweeps stray public ingress definitions, and sets an assertion tag.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#
# @security    
#              - Closes risky edge surfaces by sweeping legacy port 22/TCP fallback policies.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#              - Seals tracking updates behind structural marker files inside safe application runtimes.
#
# @exit        0  Success: Firewall structure verified; initialization steps skipped.
# @exit        10 Success: UFW subsystem fully reset, cleaned, and freshly initialised.
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
VPC_IP_RANGE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE')"

initialised="0"

if [ ! -f ${HOME}/runtime/FIREWALL-INITIALISED ]
then
        if [ ! -f ${HOME}/runtime/FIREWALL-ACTIVE ]
        then
                /usr/bin/yes | /usr/sbin/ufw reset
                
                if /usr/sbin/ufw status | /bin/grep -q "22/tcp"
                then
                        /usr/sbin/ufw delete allow 22/tcp
                fi

                /usr/sbin/ufw logging off
                VPC_IP_RANGE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE')"
                ip_addresses="$(/usr/sbin/ufw status | /bin/grep "^443" | /bin/grep -v "${VPC_IP_RANGE}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"

                for ip_address in ${ip_addresses}
                do
                        /usr/sbin/ufw delete allow from ${ip_address}
                done

                /usr/sbin/ufw reload
                initialised="1"
                /bin/touch ${HOME}/runtime/FIREWALL-INITIALISED 
        fi
fi

if [ "${initialised}" = "1" ]
then
        exit 10
else
        exit 0
fi

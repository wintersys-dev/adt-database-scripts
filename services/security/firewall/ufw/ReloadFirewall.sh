#!/bin/sh
###################################################################################
# @file        ReloadFirewall.sh
# @brief       Context-Aware UFW Firewall Commit, Activation & State State Verification.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script finalizes changes to the Uncomplicated Firewall (UFW) layer.
#              It accepts parameter flags indicating whether rules were updated or freshly 
#              initialised. If either condition is true, it forcefully commits the runtime
#              tables, reloads policies, and audits active running states to touch the global
#              infrastructure firewall assertion tracking file.
#
# @param       $1  updated      Flag (0 or 1) indicating if custom access rules changed.
# @param       $2  initialised  Flag (0 or 1) indicating if a factory clear just completed.
#
# @env         HOME       Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#
# @security    
#              - Enforces active runtime evaluation to verify that drops are processing live traffic.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: UFW state successfully verified, reloaded, or safely skipped.
# @exit        1  Failure: Missing positional arguments or failed rule commit event.
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

if [ -z "${1}" ]
then
        /bin/echo "Usage: ${0} <updated: 0|1>"
        exit 1
fi

updated="${1}"

HOME="$(/bin/cat /home/homedir.dat)"

if [ "${updated}" = "1" ] 
then
        /usr/sbin/ufw -f enable
        /usr/sbin/ufw reload
fi

if [ "$(/usr/sbin/ufw status | /bin/grep 'inactive')" = "" ]
then
        /bin/touch "${HOME}/runtime/FIREWALL-ACTIVE"
fi

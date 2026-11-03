#!/bin/sh
###################################################################################
# @file        KnickersUp.sh
# @brief       Context-Aware Firewall Lockdown Activation Execution Wrapper.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script acts as a runtime abstraction layer to instantly trigger
#              restrictive security postures (Lockdown/KnickersUp) on the firewall.
#              It extracts the targeted firewall style configuration and routes
#              execution to the corresponding engine-specific enforcement script.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractBuildStyleValues.sh parsing library evaluating software style patterns.
#              - KnickersUp.sh engine-specific lockdown module selected by parameters.
#
# @security    
#              - Relies on system-owned executable paths (/bin, /usr/bin) to circumvent hijack exploits.
#              - Isolates underlying active firewall architecture implementation details.
#
# @exit        0  Success: Firewall lockdown script invoked and executed successfully.
# @exit        1  Failure: Mismatched input states or invalid configuration.
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

firewall_type="$(${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $2}')"

${HOME}/services/security/firewall/${firewall_type}/KnickersUp.sh


#!/bin/sh
###################################################################################
# @file        AllowVPC.sh
# @brief       Context-Aware UFW Firewall Provisioning for Private VPC Network Access.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script manages internal private routing layers inside the host firewall
#              using the Uncomplicated Firewall (UFW) subsystem. It audits and explicitly
#              whitelists trusted incoming subnets defined within the Virtual Private Cloud
#              (VPC) IP pool targeting active SSH, HTTP (80), and HTTPS (443) services.
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
#              - Scopes internal network permissions tightly to targeted corporate VPC boundaries.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Firewall state verified; no new access modifications applied.
# @exit        10 Success: Active network routing tables updated with VPC subnet definitions.
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

SSH_PORT="$(${HOME}/utilities/config/ExtractConfigValue.sh 'SSHPORT')"
VPC_IP_RANGE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE')"
updated="0"

if [ "$(/usr/sbin/ufw status | /bin/grep "${SSH_PORT}.*ALLOW.*${VPC_IP_RANGE}")" = "" ]
then
        /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port ${SSH_PORT}
        /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port 443
        /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port 80
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

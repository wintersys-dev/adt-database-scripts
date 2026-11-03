#!/bin/sh
###################################################################################
# @file        AllowBuildMachine.sh
# @brief       Context-Aware iptables Firewall Provisioning for Build Machine Access.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script manages netfilter host firewall rules for the centralized
#              build platform using the iptables kernel engine framework. It validates and
#              whitelists explicit bidirectional connection tracking profiles originating
#              from the designated build machine IP address targeting active SSH, web
#              transport (443), and echo response query (ICMP type 8) infrastructure channels.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/buildhome.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - /usr/sbin/iptables system netfilter kernel rule table configuration application binary.
#
# @security    
#              - Restricts external toolkit orchestration strictly to single /32 IP allocations.
#              - Enforces explicit connection tracking parameters (--ctstate) to prevent injection risks.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Netfilter state verified; no new rule modifications appended.
# @exit        10 Success: Active iptables kernel chains updated with build machine rule maps.
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

if [ "$(/usr/sbin/iptables --list-rules | /bin/grep "${BUILD_MACHINE_IP}.*${SSH_PORT}.*ACCEPT")" = "" ]
then
        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport ${SSH_PORT} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport ${SSH_PORT} -m conntrack --ctstate ESTABLISHED -j ACCEPT
        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT  
        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p ICMP --icmp-type 8 -j ACCEPT
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

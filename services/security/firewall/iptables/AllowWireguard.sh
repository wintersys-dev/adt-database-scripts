#!/bin/sh
###################################################################################
# @file        AllowWireguard.sh
# @brief       Context-Aware iptables Firewall Provisioning for WireGuard Tunnel Access.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script manages secure overlay network tunneling layers inside the host
#              firewall using the netfilter iptables kernel framework. It dynamically
#              calculates the WireGuard listener port (derived as SSH_PORT + 1) on hosts 
#              not designated as public-facing reverse proxies and whitelists bidirectional 
#              TCP and UDP traffic tracking profiles originating from the build machine.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - /usr/sbin/iptables system netfilter kernel rule table configuration application binary.
#
# @security    
#              - Limits tunnel visibility by enforcing micro-segmentation based on hostname roles.
#              - Enforces explicit connection tracking parameters (--ctstate) to prevent injection risks.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Netfilter state verified; no new rule modifications applied.
# @exit        10 Success: Active iptables kernel chains updated with WireGuard port allocations.
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
AUTHENTICATOR_TYPE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'AUTHENTICATORTYPE')"
BUILD_MACHINE_IP="$(${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDMACHINEIP')"

updated="0"

if [ "$(/usr/bin/hostname | /bin/grep '^rp\-')" = "" ] && [ "${AUTHENTICATOR_TYPE}" = "wire-guard" ]
then
        wireguard_port="$(/usr/bin/expr "${SSH_PORT}" + 1)"
        
        if [ "$(/usr/sbin/iptables --list-rules | /bin/grep ".*${wireguard_port}.*ACCEPT")" = "" ]
        then
                /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport ${wireguard_port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport ${wireguard_port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p udp --dport ${wireguard_port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p udp --sport ${wireguard_port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                updated="1"
        fi
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

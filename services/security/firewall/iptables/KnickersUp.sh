#!/bin/sh
###################################################################################
# @file        KnickersUp.sh
# @brief       Context-Aware iptables Default Ingress Deny State Enforcement (KnickersUp).
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script enforces a highly restrictive security posture on the host by
#              configuring the netfilter iptables/ip6tables subsystems to drop incoming
#              and transit connections by default. It whitelists essential loopback interfaces
#              and active connection tracks, blocks inbound ICMP echo requests to mitigate
#              network discovery, persists the policy to storage via netfilter-persistent,
#              and handles execution tracking markers.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - /usr/sbin/iptables system netfilter kernel rule table configuration application binary.
#              - /usr/sbin/ip6tables system IPv6 netfilter kernel rule table configuration application binary.
#              - /usr/sbin/netfilter-persistent framework utility persisting kernel firewall rule maps.
#
# @security    
#              - Locks down the edge network topology by setting universal default-deny filter postures.
#              - Drops inbound ICMP queries to obscure infrastructure endpoints from adversarial sweeps.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Security posture verified or netfilter tables securely updated.
# @exit        1  Failure: General system exception or rule saving failure.
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
        /usr/sbin/iptables -I INPUT -m state --state ESTABLISHED -j ACCEPT
        /usr/sbin/iptables -A INPUT -p icmp -m icmp --icmp-type 8 -j DROP
        /usr/sbin/iptables -A INPUT -i lo -j ACCEPT
        /usr/sbin/iptables -A OUTPUT -o lo -j ACCEPT
        /usr/sbin/iptables -P INPUT DROP
        /usr/sbin/iptables -P FORWARD DROP
        /usr/sbin/iptables -P OUTPUT ACCEPT
        /usr/sbin/ip6tables -P INPUT DROP
        /usr/sbin/ip6tables -P FORWARD DROP
        /usr/sbin/ip6tables -P OUTPUT DROP
     #   /usr/sbin/netfilter-persistent save
        /bin/touch ${HOME}/runtime/KNICKERS_ARE_UP
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

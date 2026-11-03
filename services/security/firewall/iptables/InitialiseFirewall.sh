#!/bin/sh
###################################################################################
# @file        InitialiseFirewall.sh
# @brief       Context-Aware iptables Factory Reset & Core Chain Initialization Utility.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script handles netfilter state base policy provisioning across IPv4
#              and IPv6 engines using iptables and ip6tables. If an environment node hasn't 
#              been initialized, it enforces rigorous default-deny ingress and transit routing 
#              postures, whitelists structural loopback interfaces, permits critical connection 
#              tracking profiles (ESTABLISHED, RELATED), drops malformed network objects, sweeps 
#              stray edge rules, and drops a tracking assertion state flag.
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
#
# @security    
#              - Secures kernel packet forwarding layers to block unauthorized lateral traffic routing.
#              - Enforces rigorous drop filters on --ctstate INVALID states to foil exploitation vectors.
#              - Relies on system-owned executable paths (/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Netfilter baseline audited; setup initialization steps skipped.
# @exit        10 Success: Kernel filter tables fully initialized and baseline hardened.
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

#set -e

HOME="$(/bin/cat /home/homedir.dat)"
VPC_IP_RANGE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE')"

initialised="0"

if [ ! -f ${HOME}/runtime/FIREWALL-INITIALISED ]
then
        /usr/sbin/iptables -P INPUT DROP
        /usr/sbin/iptables -P FORWARD DROP
        /usr/sbin/iptables -P OUTPUT ACCEPT
        /usr/sbin/iptables -A INPUT -i lo -j ACCEPT
        /usr/sbin/iptables -A OUTPUT -o lo -j ACCEPT

        /usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        /usr/sbin/iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
        /usr/sbin/iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
        /usr/sbin/iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

        /usr/sbin/ip6tables -P INPUT DROP
        /usr/sbin/ip6tables -P FORWARD DROP
        /usr/sbin/ip6tables -P OUTPUT ACCEPT
        /usr/sbin/ip6tables -A INPUT -i lo -j ACCEPT
        /usr/sbin/ip6tables -A OUTPUT -o lo -j ACCEPT

        VPC_IP_RANGE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE')"
        ip_addresses="$(/usr/sbin/iptables -L INPUT -n | /bin/grep "443 ctstate" | /bin/grep -v "${VPC_IP_RANGE}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"

        for ip_address in ${ip_addresses}
        do
                /usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        done

        initialised="1"
        /bin/touch ${HOME}/runtime/FIREWALL-INITIALISED 
fi

if [ "${initialised}" = "1" ]
then
        exit 10
else
        exit 0
fi

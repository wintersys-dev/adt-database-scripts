#!/bin/sh
###################################################################################
# @file        AllowCustomPorts.sh
# @brief       Context-Aware iptables Rule Synchronization for Custom Target Ports.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script parses runtime firewall configuration maps to audit, append,
#              or purge custom netfilter entries inside the iptables subsystem. It dynamically
#              calculates connection rate-limiting properties, intercepts vendor proxy edge 
#              networks (Cloudflare), and synchronizes bidirectional ingress and egress 
#              states using application-specific role architectures.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - ExtractBuildStyleValues.sh parsing library evaluating software style patterns.
#              - /usr/sbin/iptables system netfilter kernel rule table configuration application binary.
#              - /usr/bin/curl network transport library targeting external vendor assets.
#
# @security    
#              - Implements target rate-limiting options to defend custom listener channels from DoS.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#              - Seals traffic patterns cleanly across specific connection tracking states.
#
# @exit        0  Success: Custom port rules evaluated; no netfilter modifications applied.
# @exit        10 Success: Active iptables kernel chains updated with custom rules.
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
set -x
set -e

HOME="$(/bin/cat /home/homedir.dat)"
NO_REVERSE_PROXIES="$(${HOME}/utilities/config/ExtractConfigValue.sh 'NOREVERSEPROXIES')"

limit="$(${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $3}')"
limit_burst="$(${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $4}')"

if [ "${limit}" = "" ] || [ "${limit_burst}" = "" ]
then
        limited="off"
else
        if [ "${limit}" -eq "${limit}" ] 2>/dev/null && [ "${limit_burst}" -eq "${limit_burst}" ] 2>/dev/null
        then
                limited="on"
        else
                limited="off"
        fi
fi

if [ "$(/usr/bin/hostname | /bin/grep '^ws-')" != "" ] && [ "${NO_REVERSE_PROXIES}" != "0" ]
then
        limited="off"
fi

updated="0"
if [ -f ${HOME}/runtime/firewall.dat ]
then
        ports=""
        if [ "$(/usr/bin/hostname | /bin/grep '\-rp-')" != "" ]
        then
                ports="$(/bin/grep "^REVERSEPROXYPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/REVERSEPROXYPORTS://g')"
        elif [ "$(/usr/bin/hostname | /bin/grep '^ws-')" != "" ]
        then
                ports="$(/bin/grep "^WEBSERVERPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/WEBSERVERPORTS://g')"
        elif [ "$(/usr/bin/hostname | /bin/grep '\-auth-')" != "" ]
        then
                ports="$(/bin/grep "^AUTHENTICATORPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/AUTHENTICATORPORTS://g')"
        fi

        for port_token in ${ports}
        do
                delete="no"
                port=""
                ip_address=""

                if [ "$(/bin/echo "${port_token}" | /bin/grep 'ipv4')" != "" ]
                then
                        port="$(/bin/echo "${port_token}" | /usr/bin/awk -F'|' '{print $1}')"
                        ip_address="$(/bin/echo "${port_token}" | /usr/bin/awk -F'|' '{print $4}')"

                        if [ "$(/bin/echo "${port_token}" | /usr/bin/awk -F'|' '{print $6}')" = "DELETE" ]
                        then
                                delete="yes"
                        fi
                fi
                cloudflare="0"
                if [ "${ip_address}" = "cloudflare" ] 
                then
                        cloudflare="1"
                fi

                ip_address_grep="${ip_address}"

                if [ "${ip_address}" = "0.0.0.0/0" ]
                then
                        ip_address_grep=""
                fi

                if [ "${cloudflare}" = "1" ]
                then
                        for ip in $(/usr/bin/curl -s https://cloudflare.com)
                        do
                                if [ "$(/usr/sbin/iptables --list-rules | /bin/grep "${ip}.*443.*ACCEPT")" = "" ]
                                then
                                        /usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                                        if [ "${limited}" = "on" ]
                                        then
                                                /usr/sbin/iptables -A INPUT -s ${ip} -p tcp --dport ${port} -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 30 -j ACCEPT
                                                /usr/sbin/iptables -A INPUT -s ${ip} -p tcp --dport ${port} -m conntrack --ctstate NEW -j DROP
                                                /usr/sbin/iptables -A OUTPUT -s ${ip} -p tcp --sport ${port} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                                        elif [ "${limited}" = "off" ]
                                        then
                                                /usr/sbin/iptables -I INPUT -s ${ip} -p tcp -m tcp --dport 443 -j ACCEPT
                                        fi
                                        updated="1"
                                fi
                        done
                elif [ "$(/usr/sbin/iptables --list-rules | /bin/grep "${ip_address_grep}.*${port}.*ACCEPT")" = "" ] && [ "${delete}" != "yes" ]
                then
                        if [ "${limited}" = "on" ]
                        then
                                /usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                                /usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW -m limit --limit ${limit}/min --limit-burst ${limit_burst} -j ACCEPT
                                /usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW -j DROP
                                /usr/sbin/iptables -A OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                        elif [ "${limited}" = "off" ]
                        then
                                /usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                                /usr/sbin/iptables -A OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        fi    
                        updated="1"
                else
                        if [ "$(/usr/sbin/iptables --list-rules | /bin/grep "${ip_address_grep}.*${port}.*ACCEPT")" != "" ] && [ "${delete}" = "yes" ]
                        then
                                if [ "${limited}" = "on" ]
                                then
                                        /usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                                        /usr/sbin/iptables -D OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                                elif [ "${limited}" = "off" ]
                                then      
                                        /usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp -m tcp --dport ${port} -j ACCEPT
                                fi
                                updated="1"
                        fi
                fi
        done
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

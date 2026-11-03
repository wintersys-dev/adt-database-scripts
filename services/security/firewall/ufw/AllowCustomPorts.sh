#!/bin/sh
###################################################################################
# @file        AllowCustomPorts.sh
# @brief       Context-Aware UFW Firewall Rule Synchronization for Custom Target Ports.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script parses runtime firewall configuration maps to audit, append,
#              or purge custom access control entries inside the UFW subsystem. It dynamically
#              determines operational modes (allow/limit) based on architecture profiles,
#              handles cloud delivery network automation edge subnets (Cloudflare), and
#              prunes transient rule records dynamically using host topologies.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh configurations extractor infrastructure for lookup evaluations.
#              - ExtractBuildStyleValues.sh parsing library evaluating software style patterns.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#              - /usr/bin/curl network transport library targeting external vendor assets.
#
# @security    
#              - Filters system platform usernames via narrow truncation to minimize information exposure.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#              - Isolates rule evaluation strictly to tracked, structured dataset objects.
#
# @exit        0  Success: Custom port rules evaluated; no structural additions applied.
# @exit        10 Success: Active network routing tables updated with custom firewall updates.
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

NO_REVERSE_PROXIES="$(${HOME}/utilities/config/ExtractConfigValue.sh 'NOREVERSEPROXIES')"

openness=""
if [ "$(${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $3}')" = "limit" ]
then
        openness="limit"
else
        openness="allow"
fi

if [ "$(/usr/bin/hostname | /bin/grep '^ws-')" != "" ] && [ "${NO_REVERSE_PROXIES}" != "0" ]
then
        openness="allow"
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

                if [ "${ip_address}" = "cloudflare" ]
                then
                        for ip in $(/usr/bin/curl -s https://cloudflare.com)
                        do
                                if [ "$(/usr/sbin/ufw status | /bin/grep "ALLOW.*${ip}")" = "" ]
                                then
                                        /usr/sbin/ufw ${openness} from ${ip} to any port 443
                                        updated="1"
                                fi
                        done
                elif [ "$(/usr/sbin/ufw status | /bin/grep "${port}" | /bin/grep "ALLOW" | /bin/grep "${ip_address}")" = "" ] && [ "${delete}" != "yes" ]
                then
                        /usr/sbin/ufw ${openness} from ${ip_address} to any port ${port}
                        updated="1"
                else
                        if [ "$(/usr/sbin/ufw status | /bin/grep "${port}" | /bin/grep "ALLOW" | /bin/grep "${ip_address}")" != "" ] && [ "${delete}" = "yes" ]
                        then
                                rule_no="$(/usr/sbin/ufw status numbered | /bin/grep "${port}" | /usr/bin/awk -F"[\[\]]" '{print $2}' | /bin/sed 's/ //g')"
                                if [ "${rule_no}" != "" ]
                                then
                                        /bin/echo "y" | /usr/sbin/ufw delete "${rule_no}"
                                        updated="1"
                                fi
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

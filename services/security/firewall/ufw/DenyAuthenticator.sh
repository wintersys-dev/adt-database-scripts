#!/bin/sh
###################################################################################
# @file        DenyAuthenticator.sh
# @brief       Context-Aware UFW Isolation Policy Blocking Authenticator Infrastructure.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     Because authenticator machines are more public facing than the other 
#              machines in our architecture, we want to block ssh requests to our 
#              infrastructure that originate from authenticator machines as they are 
#              slightly more vulnerable than our core infrastructure machines. This 
#              script queries cloud datastores to fetch internal and public tracking 
#              addresses and systematically builds default-deny UFW drops across non-auth hosts.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ListFromDatastore.sh data object wrapper pulling live environment configurations.
#              - /usr/sbin/ufw system Uncomplicated Firewall management application binary.
#
# @security    
#              - Implements lateral isolation by drop-blocking requests originating from public edges.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Isolation drop rules assessed and successfully written to UFW.
# @exit        1  Failure: General system exception or failed file validation event.
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

updated="0"
if [ "$(/usr/bin/hostname | /bin/grep '\-auth\-')" = "" ]
then
        authenticator_ip="$(${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "authenticatorip/*" | /usr/bin/tr '\n' ' ')"
        authenticator_public_ip="$(${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "authenticatorpublicip/*" | /usr/bin/tr '\n' ' ')"

        if [ "${authenticator_ip}" != "" ]
        then
                /usr/sbin/ufw deny from ${authenticator_ip}
                updated="1"
        fi

        if [ "${authenticator_public_ip}" != "" ]
        then
                /usr/sbin/ufw deny from ${authenticator_public_ip}
                updated="1"
        fi
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi

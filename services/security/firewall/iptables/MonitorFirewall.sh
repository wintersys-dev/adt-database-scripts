#!/bin/sh
###################################################################################
# @file        MonitorFirewall.sh
# @brief       Context-Aware iptables Firewall Status Tracking and Incident Alerting Utility.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script validates the live operational status of the netfilter kernel
#              firewall subsystem via netfilter-persistent and iptables rule assertions.
#              To avoid false positives, it bypasses tracking early during host uptime
#              initialisation or if structural target configurations are explicitly disabled.
#              If an inactive or unhardened policy state is detected on a fully provisioned
#              host, it fires high-severity system alerts via the framework email gateway.
#
# @param       None
#
# @env         HOME              Sourced application root tracking pathway string.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - CheckConfigValue.sh boolean validation mechanism verifying firewall targets.
#              - ListFromDatastore.sh data object wrapper pulling live installation markers.
#              - RunServiceCommand.sh host process abstraction wrapping system service states.
#              - GetPublicIP.sh tracking helper utility deriving node egress bindings.
#              - SendEmail.sh messaging engine generating systemic outbound warning vectors.
#              - /usr/sbin/iptables system netfilter kernel rule table configuration application binary.
#
# @security    
#              - Implements systemic dead-man checking to maintain infrastructure perimeter visibility.
#              - Relies on system-owned executable paths (/bin, /usr/bin, /usr/sbin) to circumvent hijack exploits.
#
# @exit        0  Success: Firewall status audited or evaluation bypassed cleanly.
# @exit        1  Failure: General system exception or missing tracking reference points.
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

if [ "$(${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:1)" = "0" ] && [ "$(${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:3)" = "0" ]
then
        exit 0
fi

if [ "$(/bin/cat /proc/uptime | /usr/bin/awk -F'.' '{print $1}')" -lt "600" ]
then
        exit 0
fi

if [ "$(${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "INSTALLED_SUCCESSFULLY")" = "" ]
then
        exit 0
fi

if [ "$(${HOME}/utilities/processing/RunServiceCommand.sh netfilter-persistent status | /bin/grep Loaded | /bin/grep enabled)" = "" ]
then
        if [ "$(${HOME}/utilities/processing/RunServiceCommand.sh netfilter-persistent status | /bin/grep active)" = "" ] || [ "$(/usr/sbin/iptables --list-rules | /bin/grep '\-P INPUT DROP')" = "" ]
        then
                public_ip="$(${HOME}/utilities/processing/GetPublicIP.sh)"
                
                ${HOME}/services/email/SendEmail.sh \
                        "FIREWALL (iptables) INACTIVE" \
                        "Just so you know, your firewall is inactive on machine ${public_ip}. The machine may still be initialising after a reboot, which can take some minutes, but if these messages continue indefinitely, then you need to look into why the firewall is inactive." \
                        "ERROR"
                        
                if [ -f ${HOME}/runtime/FIREWALL-ACTIVE ]
                then
                        /bin/rm "${HOME}/runtime/FIREWALL-ACTIVE"
                fi
        fi
fi

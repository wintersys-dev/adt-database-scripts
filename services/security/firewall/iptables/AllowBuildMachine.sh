#!/bin/sh
#: Name:        AllowBuildMachine.sh
#: Purpose:     Provisions idempotent iptables rules permitting SSH, HTTPS, and ICMP from the build machine.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       AllowBuildMachine.sh
#:              AllowBuildMachine.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads BUILDMACHINEIP and SSHPORT from configuration and enforces iptables rules.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - /usr/sbin/iptables
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Netfilter rules already present; no changes made
#:   1          Missing /home/homedir.dat, missing config values, or iptables execution failure
#:   10         Active iptables chains updated with build machine rules (signals ReloadFirewall.sh)
###################################################################################
# License Agreement:
# This file is part of The Wintersys Agile Deployment Toolkit.
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
####################################################################################

# Exit immediately if any command exits with a non-zero status
#set -x
set -e

# Render self-extracting help documentation when -h or --help is supplied
if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]
then
        /usr/bin/grep '^#:' "$0" | /usr/bin/cut -c 4-
        exit 0
fi

# Resolve the server toolkit root directory from /home/homedir.dat
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
        export HOME
else
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: Resolved HOME directory '${HOME}' is invalid." >&2
        exit 1
fi

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
if [ ! -x "${config_extractor}" ]
then
        /bin/echo "Error: ExtractConfigValue.sh missing or not executable at ${config_extractor}" >&2
        exit 1
fi

set +e
BUILD_MACHINE_IP="$("${config_extractor}" 'BUILDMACHINEIP')"
SSH_PORT="$("${config_extractor}" 'SSHPORT')"
set -e

if [ -z "${BUILD_MACHINE_IP}" ] || [ -z "${SSH_PORT}" ]
then
        /bin/echo "Error: Required configuration values (BUILDMACHINEIP or SSHPORT) are missing." >&2
        exit 1
fi

if [ ! -x /usr/sbin/iptables ]
then
        /bin/echo "Error: /usr/sbin/iptables not found or not executable." >&2
        exit 1
fi

updated="0"

ensure_rule()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -A "$@"
                updated="1"
        fi
}

ensure_rule INPUT -s "${BUILD_MACHINE_IP}/32" -p tcp --dport "${SSH_PORT}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
ensure_rule OUTPUT -d "${BUILD_MACHINE_IP}/32" -p tcp --sport "${SSH_PORT}" -m conntrack --ctstate ESTABLISHED -j ACCEPT
ensure_rule INPUT -s "${BUILD_MACHINE_IP}/32" -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
ensure_rule OUTPUT -d "${BUILD_MACHINE_IP}/32" -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
ensure_rule INPUT -s "${BUILD_MACHINE_IP}/32" -p icmp --icmp-type 8 -j ACCEPT

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


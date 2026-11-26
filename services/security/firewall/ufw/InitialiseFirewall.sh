#!/bin/sh
#: Name:        InitialiseFirewall.sh
#: Purpose:     Resets UFW to a clean baseline, removes default 22/tcp rules, disables logging, and sweeps stray 443 rules.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       InitialiseFirewall.sh
#:              InitialiseFirewall.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads VPCIPRANGE from configuration and initializes UFW baseline state once.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut, yes, mkdir, touch
#:
#: Exit Codes:
#:   0          UFW baseline already initialized or active; no changes made
#:   1          Missing /home/homedir.dat, missing /usr/sbin/ufw, or reset failure
#:   10         UFW subsystem reset and freshly initialized (signals ReloadFirewall.sh)
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

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

initialised="0"
runtime_dir="${HOME}/runtime"
init_flag="${runtime_dir}/FIREWALL-INITIALISED"
active_flag="${runtime_dir}/FIREWALL-ACTIVE"

if [ ! -f "${init_flag}" ] && [ ! -f "${active_flag}" ]
then
        /usr/bin/yes | /usr/sbin/ufw reset >/dev/null

        if /usr/sbin/ufw status | /bin/grep -q "22/tcp"
        then
                /usr/sbin/ufw delete allow 22/tcp >/dev/null 2>&1 || true
        fi

        /usr/sbin/ufw logging off >/dev/null

        set +e
        VPC_IP_RANGE="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'VPCIPRANGE')"
        ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
        set -e

        vpc_prefix=""
        if [ -n "${VPC_IP_RANGE}" ]
        then
                vpc_prefix="${VPC_IP_RANGE%/*}"
        fi

        set +e
        if [ -n "${vpc_prefix}" ]
        then
                ip_addresses="$(printf '%s\n' "${ufw_status}" | /bin/grep "^443" | /bin/grep -Fv "${vpc_prefix}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"
        else
                ip_addresses="$(printf '%s\n' "${ufw_status}" | /bin/grep "^443" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"
        fi
        set -e

        for ip_address in ${ip_addresses}
        do
                /usr/sbin/ufw delete allow from "${ip_address}" to any port 443 >/dev/null 2>&1 || true
                /usr/sbin/ufw delete allow from "${ip_address}" >/dev/null 2>&1 || true
        done

        /usr/sbin/ufw reload >/dev/null 2>&1 || true

        if [ ! -d "${runtime_dir}" ]
        then
                /bin/mkdir -p "${runtime_dir}"
        fi

        initialised="1"
        /usr/bin/touch "${init_flag}"
fi

if [ "${initialised}" = "1" ]
then
        exit 10
else
        exit 0
fi


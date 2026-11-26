#!/bin/sh
#: Name:        AllowVPC.sh
#: Purpose:     Provisions idempotent UFW rules permitting SSH, DB, HTTP, and HTTPS access from the private VPC subnet.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       AllowVPC.sh
#:              AllowVPC.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads SSHPORT, DBPORT, and VPCIPRANGE from configuration and enforces UFW rules.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut
#:
#: Exit Codes:
#:   0          UFW VPC rules already present; no changes made
#:   1          Missing /home/homedir.dat, missing config values, or UFW execution failure
#:   10         Active UFW ruleset updated with VPC subnet rules (signals ReloadFirewall.sh)
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
SSH_PORT="$("${config_extractor}" 'SSHPORT')"
DB_PORT="$("${config_extractor}" 'DBPORT')"
VPC_IP_RANGE="$("${config_extractor}" 'VPCIPRANGE')"
set -e

if [ -z "${VPC_IP_RANGE}" ] || [ -z "${SSH_PORT}" ]
then
        /bin/echo "Error: Required configuration values (VPCIPRANGE or SSHPORT) are missing." >&2
        exit 1
fi

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

set +e
ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
set -e

updated="0"

ensure_ufw_vpc_port()
{
        target_port="${1}"
        if ! printf '%s\n' "${ufw_status}" | /bin/grep -Eq "^${target_port}(/tcp)?[[:space:]]+ALLOW[[:space:]]+${VPC_IP_RANGE}([[:space:]]|$)"
        then
                /usr/sbin/ufw allow from "${VPC_IP_RANGE}" to any port "${target_port}" >/dev/null
                updated="1"
        fi
}

ensure_ufw_vpc_port "${SSH_PORT}"

if [ -n "${DB_PORT}" ] && [ "${DB_PORT}" -eq "${DB_PORT}" ] 2>/dev/null
then
        ensure_ufw_vpc_port "${DB_PORT}"
fi

ensure_ufw_vpc_port 443
ensure_ufw_vpc_port 80

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


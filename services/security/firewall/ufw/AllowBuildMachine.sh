#!/bin/sh
#: Name:        AllowBuildMachine.sh
#: Purpose:     Provisions idempotent UFW rules permitting SSH and HTTPS access from the build machine.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       AllowBuildMachine.sh
#:              AllowBuildMachine.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads BUILDMACHINEVPC, BUILDMACHINEIP, and SSHPORT from configuration and enforces UFW rules.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut, sleep
#:
#: Exit Codes:
#:   0          UFW rules verified or BUILDMACHINEVPC != 0; no changes made
#:   1          Missing /home/homedir.dat, missing config values, or UFW execution failure
#:   10         Active UFW ruleset updated with build machine rules (signals ReloadFirewall.sh)
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
config_checker="${HOME}/utilities/config/CheckConfigValue.sh"

if [ ! -x "${config_extractor}" ] || [ ! -x "${config_checker}" ]
then
        /bin/echo "Error: Configuration helper scripts missing or not executable under ${HOME}/utilities/config/" >&2
        exit 1
fi

if [ "$("${config_checker}" 'BUILDMACHINEVPC:0')" != "1" ]
then
        exit 0
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

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

set +e
ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
set -e

updated="0"

if ! printf '%s\n' "${ufw_status}" | /bin/grep -Eq "^${SSH_PORT}(/tcp)?[[:space:]]+ALLOW[[:space:]]+${BUILD_MACHINE_IP}(/32)?([[:space:]]|$)"
then
        /usr/sbin/ufw allow from "${BUILD_MACHINE_IP}/32" to any port "${SSH_PORT}" >/dev/null
        updated="1"
fi

if ! printf '%s\n' "${ufw_status}" | /bin/grep -Eq "^443(/tcp)?[[:space:]]+ALLOW[[:space:]]+${BUILD_MACHINE_IP}(/32)?([[:space:]]|$)"
then
        /usr/sbin/ufw allow from "${BUILD_MACHINE_IP}/32" to any port 443 >/dev/null
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        /bin/sleep 2
        exit 10
else
        exit 0
fi


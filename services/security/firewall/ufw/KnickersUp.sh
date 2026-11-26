#!/bin/sh
#: Name:        KnickersUp.sh
#: Purpose:     Enforces default-deny UFW ingress posture and default-allow egress policy (KnickersUp).
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       KnickersUp.sh
#:              KnickersUp.sh [-h|--help]
#:
#: Parameters:
#:   None       Applies UFW default deny incoming / allow outgoing once and records ${HOME}/runtime/KNICKERS_ARE_UP.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - /usr/sbin/ufw
#:   - /usr/bin/sudo
#:   - External binaries: cat, echo, printf, grep, cut, mkdir, touch, sleep, id
#:
#: Exit Codes:
#:   0          UFW default lockdown posture already active; no changes made
#:   1          Missing /home/homedir.dat, missing /usr/sbin/ufw, or privilege escalation failure
#:   10         Active UFW default policies updated with lockdown posture (signals ReloadFirewall.sh)
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

updated="0"
runtime_dir="${HOME}/runtime"
lockdown_flag="${runtime_dir}/KNICKERS_ARE_UP"

if [ ! -f "${lockdown_flag}" ]
then
        if [ "$(/usr/bin/id -u)" -eq 0 ]
        then
                /usr/sbin/ufw default deny incoming >/dev/null
                /bin/sleep 2
                /usr/sbin/ufw default allow outgoing >/dev/null
        else
                set +e
                SERVER_USER_PASSWORD="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'SERVERUSERPASSWORD')"
                set -e
                printf '%s\n' "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /usr/sbin/ufw default deny incoming >/dev/null
                /bin/sleep 2
                printf '%s\n' "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /usr/sbin/ufw default allow outgoing >/dev/null
        fi

        if [ ! -d "${runtime_dir}" ]
        then
                /bin/mkdir -p "${runtime_dir}"
        fi

        /usr/bin/touch "${lockdown_flag}"
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


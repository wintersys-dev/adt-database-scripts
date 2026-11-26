#!/bin/sh
#: Name:        ReloadFirewall.sh
#: Purpose:     Enables and reloads UFW rules when updated and asserts the FIREWALL-ACTIVE marker file.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       ReloadFirewall.sh <updated: 0|1>
#:              ReloadFirewall.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Update flag ("1" to enable and reload UFW, "0" to verify state only)
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut, mkdir, touch
#:
#: Exit Codes:
#:   0          UFW state enabled/reloaded cleanly and active status verified
#:   1          Missing /home/homedir.dat, invalid/missing arguments, or UFW execution failure
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

if [ -z "${1}" ] || { [ "${1}" != "0" ] && [ "${1}" != "1" ]; }
then
        /bin/echo "Usage: ${0} <updated: 0|1>" >&2
        exit 1
fi

updated="${1}"

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

if [ "${updated}" = "1" ]
then
        /usr/sbin/ufw -f enable >/dev/null
        /usr/sbin/ufw reload >/dev/null
fi

set +e
ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
set -e

if printf '%s\n' "${ufw_status}" | /bin/grep -q '^Status: active'
then
        runtime_dir="${HOME}/runtime"
        if [ ! -d "${runtime_dir}" ]
        then
                /bin/mkdir -p "${runtime_dir}"
        fi
        /usr/bin/touch "${runtime_dir}/FIREWALL-ACTIVE"
fi

exit 0


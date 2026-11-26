#!/bin/sh
#: Name:        SetupFirewallFromCron.sh
#: Purpose:     Cron-invoked wrapper that enforces firewall configuration using a stale-safe atomic lockfile.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       SetupFirewallFromCron.sh
#:              SetupFirewallFromCron.sh [-h|--help]
#:
#: Parameters:
#:   None       Uses a 20-minute stale-expiring lockfile at ${HOME}/runtime/firewalllock.file.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/security/firewall/SetupFirewall.sh
#:   - External binaries: cat, echo, grep, cut, find, mkdir, rm
#:
#: Exit Codes:
#:   0          Firewall setup executed cleanly or skipped safely because another instance is active
#:   1          Missing /home/homedir.dat, missing SetupFirewall.sh, or firewall setup failure
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

runtime_dir="${HOME}/runtime"
if [ ! -d "${runtime_dir}" ]
then
        /bin/mkdir -p "${runtime_dir}"
fi

lockfile="${runtime_dir}/firewalllock.file"
lock_acquired="0"

cleanup()
{
        exit_code="$?"
        if [ "${lock_acquired}" = "1" ]
        then
                /bin/rm -f "${lockfile}"
        fi
        exit "${exit_code}"
}
trap cleanup EXIT HUP INT QUIT ABRT ALRM TERM

# Remove any stale lockfile older than 20 minutes
if [ -f "${lockfile}" ]
then
        /usr/bin/find "${lockfile}" -mmin +20 -type f -exec /bin/rm -f {} + 2>/dev/null || true
fi

# Atomically acquire the lockfile using POSIX noclobber (set -C)
if ( set -C; printf '%s\n' "$$" > "${lockfile}" ) 2>/dev/null
then
        lock_acquired="1"
        firewall_script="${HOME}/services/security/firewall/SetupFirewall.sh"

        if [ ! -x "${firewall_script}" ]
        then
                /bin/echo "Error: Firewall setup script missing or not executable at ${firewall_script}" >&2
                exit 1
        fi

        "${firewall_script}"
else
        /bin/echo "Firewall setup script already running."
fi

exit 0


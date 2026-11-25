#!/bin/sh
#: Name:        PerformEmergencyRestorationFromCron.sh
#: Purpose:     Cron-triggered orchestrator that checks the config datastore for emergency restoration markers and executes recovery.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       PerformEmergencyRestorationFromCron.sh
#:              PerformEmergencyRestorationFromCron.sh [-h|--help]
#:
#: Parameters:
#:   None       Polls ACTIVATE_RESTORATION marker via ListFromDatastore.sh.
#:
#: Environment:
#:   HOME       Root directory of the server deployment toolkit
#:
#: Dependencies:
#:   - ${HOME}/services/datastore/operations/ListFromDatastore.sh
#:   - ${HOME}/services/datastore/operations/DeleteFromDatastore.sh
#:   - ${HOME}/application/backup/EmergencyRestoration.sh
#:   - External binaries: echo, grep, cut, mkdir, rm, sleep
#:
#: Exit Codes:
#:   0          Emergency restoration completed cleanly, or skipped (no marker / already in progress)
#:   1          Missing HOME environment, missing restoration script, or restoration execution failure
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
# along with The Wintersys Agile Deployment Toolkit.  If not, see <http://gnu.org>.
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

# Verify that HOME is set in the cron execution environment
if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: HOME environment variable is unset or invalid." >&2
        exit 1
fi

# Ensure runtime directory exists
runtime_dir="${HOME}/runtime"
if [ ! -d "${runtime_dir}" ]
then
        /bin/mkdir -p "${runtime_dir}"
fi

# Exit immediately if an emergency restoration is already running
lockfile="${runtime_dir}/EMERGENCY_RESTORATION_IN_PROGRESS"
if [ -f "${lockfile}" ]
then
        exit 0
fi

# Poll the config datastore for an active emergency restoration trigger marker
list_script="${HOME}/services/datastore/operations/ListFromDatastore.sh"
if [ ! -x "${list_script}" ]
then
        /bin/echo "Error: Datastore list script missing or not executable at ${list_script}" >&2
        exit 1
fi

set +e
marker="$("${list_script}" "config" "ACTIVATE_RESTORATION" | /bin/grep -o "ACTIVATE_RESTORATION.*")"
set -e

if [ -z "${marker}" ]
then
        exit 0
fi

# Acquire atomic lockfile before starting emergency restoration
if ! (set -C; : > "${lockfile}") 2>/dev/null
then
        exit 0
fi

# Guarantee lockfile removal if the script exits or is interrupted mid-restoration
cleanup()
{
        /bin/rm -f "${lockfile}"
}
trap cleanup EXIT INT TERM HUP QUIT

# Verify and execute the emergency restoration workflow
restore_script="${HOME}/application/backup/EmergencyRestoration.sh"
if [ ! -x "${restore_script}" ]
then
        /bin/echo "Error: Emergency restoration script missing or not executable at ${restore_script}" >&2
        exit 1
fi

set +e
"${restore_script}"
restore_exit_code="$?"
set -e

if [ "${restore_exit_code}" -ne 0 ]
then
        /bin/echo "Error: EmergencyRestoration.sh failed with exit code ${restore_exit_code}." >&2
        exit 1
fi

# Cooldown period before clearing the restoration trigger marker
/bin/sleep 120

# Remove the processed trigger marker from the local config datastore
delete_script="${HOME}/services/datastore/operations/DeleteFromDatastore.sh"
if [ -x "${delete_script}" ]
then
        "${delete_script}" "config" "${marker}" "local"
else
        /bin/echo "Error: Datastore delete script missing or not executable at ${delete_script}" >&2
        exit 1
fi

exit 0



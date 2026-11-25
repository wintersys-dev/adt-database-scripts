#!/bin/sh
#: Name:        BackupFromCron.sh
#: Purpose:     Cron-triggered database backup orchestrator with multi-region leader election.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       BackupFromCron.sh <periodicity>
#:              BackupFromCron.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Backup periodicity tier (e.g. "HOURLY", "DAILY", "WEEKLY", "MONTHLY")
#:
#: Environment:
#:   HOME       Root directory of the server deployment toolkit
#:
#: Dependencies:
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/datastore/operations/GetFromDatastore.sh
#:   - ${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh
#:   - ${HOME}/services/datastore/config/wrapper/PutToDatastore.sh
#:   - ${HOME}/services/datastore/config/wrapper/DeleteFromDatastore.sh
#:   - ${HOME}/application/backup/Backup.sh
#:   - External binaries: cat, echo, grep, cut, mkdir, rm, date, shuf, sleep
#:
#: Exit Codes:
#:   0          Database backup completed cleanly, or skipped (recent multi-region backup / peer authoritative)
#:   1          Missing HOME environment, missing periodicity argument, or backup execution failure
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

# Validate that the required backup periodicity argument was provided
if [ -z "${1}" ]
then
        /bin/echo "Error: Backup periodicity argument is required." >&2
        /bin/echo "Usage: $0 <periodicity>" >&2
        exit 1
fi

periodicity="${1}"

# Determine whether multi-region coordination is enabled
config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
if [ ! -x "${config_extractor}" ]
then
        /bin/echo "Error: Config extractor missing or not executable at ${config_extractor}" >&2
        exit 1
fi

MULTI_REGION="$("${config_extractor}" 'MULTIREGION')"
workarea="${HOME}/runtime/datastore_workarea"
timestamp_file="${workarea}/time_backup_written"
lock_acquired="0"

# Coordinate across regions when MULTIREGION=1 to ensure only one region runs the DB backup
if [ "${MULTI_REGION}" = "1" ]
then
        if [ ! -d "${workarea}" ]
        then
                /bin/mkdir -p "${workarea}"
        fi

        /bin/rm -f "${timestamp_file}"

        get_script="${HOME}/services/datastore/operations/GetFromDatastore.sh"
        if [ ! -x "${get_script}" ]
        then
                /bin/echo "Error: Datastore get script missing or not executable at ${get_script}" >&2
                exit 1
        fi

        set +e
        "${get_script}" "backup-db" "time_backup_written" "${workarea}" "${periodicity}"
        set -e

        # Skip backup cycle if another region wrote a valid timestamp within the last 300 seconds
        if [ -r "${timestamp_file}" ]
        then
                current_time="$(/usr/bin/date +%s)"
                backup_time="$(/bin/cat "${timestamp_file}")"

                case "${backup_time}" in
                        ''|*[!0-9]*)
                                /bin/echo "Warning: Invalid backup timestamp content in ${timestamp_file}; ignoring." >&2
                                ;;
                        *)
                                elapsed=$((current_time - backup_time))
                                if [ "${elapsed}" -lt 300 ]
                                then
                                        exit 0
                                fi
                                ;;
                esac
        fi
        # Jitter startup across regions to stagger leader election
        jitter="$(/usr/bin/shuf -i1-300 -n1)"
        /bin/sleep "${jitter}"

        list_script="${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh"
        put_script="${HOME}/services/datastore/config/wrapper/PutToDatastore.sh"
        delete_script="${HOME}/services/datastore/config/wrapper/DeleteFromDatastore.sh"

        if [ ! -x "${list_script}" ] || [ ! -x "${put_script}" ] || [ ! -x "${delete_script}" ]
        then
                /bin/echo "Error: One or more datastore config wrapper scripts are missing or not executable." >&2
                exit 1
        fi

        running_flag="$("${list_script}" "config" "DB_BACKUP_RUNNING")"
        if [ -n "${running_flag}" ]
        then
                exit 0
        fi

        # Claim distributed DB backup leadership and guarantee lock cleanup on exit or failure
        "${put_script}" "config" "DB_BACKUP_RUNNING" "root" "yes"
        lock_acquired="1"

        cleanup()
        {
                if [ "${lock_acquired}" = "1" ]
                then
                        "${delete_script}" "config" "DB_BACKUP_RUNNING" >/dev/null 2>&1 || true
                fi
                /bin/rm -f "${timestamp_file}"
        }
        trap cleanup EXIT INT TERM HUP QUIT
fi

# Verify and execute the database backup workflow
backup_script="${HOME}/application/backup/Backup.sh"
if [ ! -x "${backup_script}" ]
then
        /bin/echo "Error: Backup script missing or not executable at ${backup_script}" >&2
        exit 1
fi

set +e
"${backup_script}" "${periodicity}"
backup_exit_code="$?"
set -e

if [ "${backup_exit_code}" -ne 0 ]
then
        /bin/echo "Error: Backup.sh failed with exit code ${backup_exit_code}." >&2
        exit 1
fi

# Hold distributed lock for 300 seconds after completion so straggling regions still see it
if [ "${MULTI_REGION}" = "1" ]
then
        /bin/sleep 300
fi

exit 0


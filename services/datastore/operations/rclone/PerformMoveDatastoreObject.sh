#!/bin/sh
#: Name:        PerformMoveDatastoreObject.sh
#: Purpose:     Automated S3 datastore object relocation and server-side renaming driver using rclone.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       PerformMoveDatastoreObject.sh <original_object> <new_object> <count>
#:              PerformMoveDatastoreObject.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Source bucket and object key path inside S3
#:   $2         [Required] Destination bucket and new object key path inside S3
#:   $3         [Required] Integer configuration ID selecting /root/.config/rclone/rclone.conf-<count>
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - /usr/bin/rclone
#:   - /root/.config/rclone/rclone.conf-<count>
#:   - External binaries: cat, echo, grep, cut, date, dirname, mkdir, awk, tr, sleep
#:
#: Exit Codes:
#:   0          Server-side object relocation or renaming completed cleanly
#:   1          Missing /home/homedir.dat, missing arguments, missing rclone config, or move failure
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
else
        /bin/echo "Error: Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ ! -d "${HOME}/runtime/logs/datastore" ]
then
        /bin/mkdir -p "${HOME}/runtime/logs/datastore"
fi

LOG_FILE="${HOME}/runtime/logs/datastore/MoveDatastoreObject.log"

log_error() {
    /bin/echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

# Execute a command up to max_attempts times with a short sleep between failures
retry_command()
{
        max_attempts=5
        sleep_interval=3
        attempt=1

        while true
        do
                set +e
                "$@"
                exit_code="$?"
                set -e

                if [ "${exit_code}" -eq 0 ]
                then
                        return 0
                fi

                if [ "${attempt}" -ge "${max_attempts}" ]
                then
                        log_error  "Error: Datastore command failed after ${max_attempts} attempts (exit code ${exit_code})."
                        return "${exit_code}"
                fi

                log_error  "Warning: Datastore command failed (attempt ${attempt}/${max_attempts}). Retrying in ${sleep_interval}s..."
                attempt="$(/usr/bin/expr "${attempt}" + 1)"
                /bin/sleep "${sleep_interval}"
        done
}


if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]
then
    /bin/echo "Error: 3 arguments are required."
    /bin/echo "Usage: $0 <original_object> <new_object> <count>"
    log_error "Script invoked with missing arguments."
    exit 1
fi

original_object="$1"
new_object="$2"
count="$3"

cfg_file="/root/.config/rclone/rclone.conf-${count}"
if [ ! -f "$cfg_file" ]
then
    /bin/echo "Error: Configuration profile $cfg_file not found."
    log_error "Profile configuration file missing: $cfg_file"
    exit 1
fi

host_base=$(/usr/bin/grep ^endpoint "$cfg_file" | /usr/bin/awk -F'=' '{print $NF}' | /usr/bin/tr -d ' ')

set +e
retry_command /usr/bin/rclone --config "$cfg_file" --s3-endpoint "$host_base" moveto "s3:${original_object}" "s3:${new_object}" >/dev/null 2>&1
rclone_status=$?
set -e

if [ $rclone_status -ne 0 ]
then
    /bin/echo "Failed to move object ${original_object} to object ${new_object}"
    log_error "rclone failed to move object s3:${original_object} to s3:${new_object} (Exit code: $rclone_status)"
    exit 1
fi

exit 0

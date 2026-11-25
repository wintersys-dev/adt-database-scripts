#!/bin/sh
#: Name:        PerformPutToDatastore.sh
#: Purpose:     Automated local payload ingestion and S3 datastore storage driver using s3cmd.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       PerformPutToDatastore.sh <file_to_put> <place_to_put> <delete> <count>
#:              PerformPutToDatastore.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Local file path (or virtual marker filename) to ingest into S3
#:   $2         [Required] Target S3 bucket and destination path (trailing "root" is stripped)
#:   $3         [Required] Post-upload local source deletion flag ("yes" or "no")
#:   $4         [Required] Integer configuration ID selecting /root/.s3cfg-<count>
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - /usr/bin/s3cmd
#:   - /root/.s3cfg-<count>
#:   - External binaries: cat, echo, grep, cut, date, dirname, mkdir, touch, rm, awk, tr, sleep
#:
#: Exit Codes:
#:   0          Local payload or virtual marker uploaded cleanly to the target S3 datastore
#:   1          Missing /home/homedir.dat, missing arguments, missing s3cmd config, or upload failure
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

LOG_FILE="${HOME}/runtime/logs/datastore/PutToDatastore.log"

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
                        log_error "Error: Datastore command failed after ${max_attempts} attempts (exit code ${exit_code})."
                        return "${exit_code}"
                fi

                log_error "Warning: Datastore command failed (attempt ${attempt}/${max_attempts}). Retrying in ${sleep_interval}s..."
                attempt="$(/usr/bin/expr "${attempt}" + 1)"
                /bin/sleep "${sleep_interval}"
        done
}


if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]
then
    /bin/echo "Error: 4 arguments are required."
    /bin/echo "Usage: $0 <file_to_put> <place_to_put> <delete> <count>"
    log_error "Script invoked with missing arguments."
    exit 1
fi

file_to_put="$1"
place_to_put="$2"
delete="$3"
count="$4"

place_to_put="${place_to_put%root}"

WORK_AREA="${HOME}/runtime/datastore_workarea"
if [ ! -d "$WORK_AREA" ]
then
    /bin/mkdir -p "$WORK_AREA"
fi

if [ ! -f "$file_to_put" ]
then
    /bin/touch "$WORK_AREA/$file_to_put"
    file_to_put_with_path="$WORK_AREA/$file_to_put"
else
    file_to_put_with_path="$file_to_put"
fi

cfg_file="/root/.s3cfg-${count}"
if [ ! -f "$cfg_file" ]
then
    /bin/echo "Error: Configuration profile $cfg_file not found."
    log_error "Profile configuration file missing: $cfg_file"
    exit 1
fi

host_base=$(/usr/bin/grep ^host_base "$cfg_file" | /usr/bin/awk -F'=' '{print $NF}' | /usr/bin/tr -d ' ')

set +e
retry_command /usr/bin/s3cmd --config="$cfg_file" --host="https://${host_base}" put "$file_to_put_with_path" "s3://${place_to_put}" >/dev/null 2>&1
s3cmd_status=$?
set -e

if [ $s3cmd_status -ne 0 ]
then
    /bin/echo "Failed to put ${file_to_put_with_path} to s3://${place_to_put}"
    log_error "s3cmd failed to upload ${file_to_put_with_path} to s3://${place_to_put} (Exit code: $s3cmd_status)"
    exit 1
fi

if [ "$delete" = "yes" ]
then
    if [ -f "$file_to_put_with_path" ]
    then
        /bin/rm "$file_to_put_with_path"
    fi
fi

exit 0

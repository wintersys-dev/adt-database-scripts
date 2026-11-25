#!/bin/sh
#: Name:        PerformDatastoreMount.sh
#: Purpose:     Automated S3 datastore bucket verification and creation driver using s5cmd.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       PerformDatastoreMount.sh <datastore_to_mount> <count>
#:              PerformDatastoreMount.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Target S3 bucket name to verify or provision
#:   $2         [Required] Integer configuration ID selecting /root/.s5cfg-<count>
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - /usr/bin/s5cmd
#:   - /root/.s5cfg-<count>
#:   - External binaries: cat, echo, grep, cut, date, dirname, mkdir, awk, tr, sleep
#:
#: Exit Codes:
#:   0          Target bucket exists or was provisioned cleanly in the S3 backend
#:   1          Missing /home/homedir.dat, missing arguments, missing s5cmd config, or creation failure
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

LOG_FILE="${HOME}/runtime/logs/datastore/MountDatastore.log"

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


if [ -z "$1" ] || [ -z "$2" ]
then
    /bin/echo "Error: 2 arguments are required."
    /bin/echo "Usage: $0 <datastore_to_mount> <count>"
    log_error "Script invoked with missing arguments."
    exit 1
fi

datastore_to_mount="$1"
count="$2"

cfg_file="/root/.s5cfg-${count}"
if [ ! -f "$cfg_file" ]
then
    /bin/echo "Error: Configuration profile $cfg_file not found."
    log_error "Profile configuration file missing: $cfg_file"
    exit 1
fi

host_base=$(/usr/bin/grep ^host_base "$cfg_file" | /usr/bin/awk -F'=' '{print $NF}' | /usr/bin/tr -d ' ')

set +e

check_output="$(retry_command /usr/bin/s5cmd --credentials-file "$cfg_file" --endpoint-url "https://${host_base}" ls "s3://${datastore_to_mount}" 2>/dev/null)"
check_status=$?

if [ $check_status -ne 0 ] || [ -z "$check_output" ]
then
    retry_command /usr/bin/s5cmd --credentials-file "$cfg_file" --endpoint-url "https://${host_base}" mb "s3://${datastore_to_mount}" >/dev/null 2>&1
    mb_status=$?
    
    if [ $mb_status -ne 0 ]
    then
        /bin/echo "Failed to mount bucket s3://${datastore_to_mount}"
        log_error "s5cmd failed to create bucket s3://${datastore_to_mount} (Exit code: $mb_status)"
        exit 1
    fi
fi
set -e

exit 0

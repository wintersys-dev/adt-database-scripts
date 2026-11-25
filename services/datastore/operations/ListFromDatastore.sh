#!/bin/sh
#: Name:        ListFromDatastore.sh
#: Purpose:     Context-aware S3 datastore object and sub-path metadata listing utility.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       ListFromDatastore.sh <bucket_type> <file_to_list> [additional_specifier]
#:              ListFromDatastore.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Target bucket classification type (e.g., ssl, config, asset, backup-web, backup-db, ad-hoc)
#:   $2         [Required] File name or relative object/directory path to inspect (pass "root" for bucket root)
#:   $3         [Optional] Contextual tracking suffix or explicit bucket name for "ad-hoc" mode
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/datastore/operations/ResolveBucketName.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/services/datastore/operations/<DATASTORETOOL>/PerformListFromDatastore.sh
#:   - External binaries: cat, echo, grep, cut, date, dirname, mkdir, awk
#:
#: Exit Codes:
#:   0          Datastore structural inspection and item listing completed cleanly
#:   1          Missing /home/homedir.dat, missing arguments, or missing/failed driver scripts
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

LOG_FILE="${HOME}/runtime/logs/datastore/ListFromDatastore.log"

log_error()
{
        error_msg="[$(/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: ${1}"
        /bin/echo "${error_msg}" >&2
        
        if [ -w "${LOG_FILE}" ] || [ -w "$(/usr/bin/dirname "${LOG_FILE}")" ]
        then
                /bin/echo "${error_msg}" >> "${LOG_FILE}"
        fi
}

if [ -z "${1}" ] || [ -z "${2}" ]
then
        log_error "2 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <bucket_type> <file_to_list> <additional_specifier>" >&2
        exit 1
fi

bucket_type="${1}"
file_to_list="${2}"
additional_specifier="${3}"

if [ "${file_to_list}" = "root" ]
then
        file_to_list=""
fi


resolver_script="${HOME}/services/datastore/operations/ResolveBucketName.sh"
if [ ! -f "${resolver_script}" ] || [ ! -x "${resolver_script}" ]
then
        status "Error: Bucket resolver script missing or not executable at ${resolver_script}"
        exit 1
fi

active_bucket="$("${resolver_script}" "${bucket_type}" "${additional_specifier}")"

DATASTORE_TOOL="$("${HOME}/utilities/config/ExtractBuildStyleValues.sh" "DATASTORETOOL" | /usr/bin/awk -F':' '{print $2}')"

execution_driver="${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformListFromDatastore.sh"

if ! "${execution_driver}" "${active_bucket}/${file_to_list}"
then
        log_error "PerformListFromDatastore.sh driver execution failed returned an error code"
        exit 1
fi

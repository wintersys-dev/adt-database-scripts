#!/bin/sh
#: Name:        PutToDatastore.sh
#: Purpose:     Context-aware S3 datastore object and asset upload utility across local or distributed endpoints.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       PutToDatastore.sh <bucket_type> <file_to_put> <place_to_put> <mode> <delete> [additional_specifier]
#:              PutToDatastore.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Target bucket classification type (e.g., ssl, config, asset, backup-web, backup-db, ad-hoc)
#:   $2         [Required] Absolute or relative local path of the file to upload
#:   $3         [Required] Target destination folder path within the bucket (pass "root" for bucket root)
#:   $4         [Required] Execution topology mode ("local" or "distributed")
#:   $5         [Required] Post-upload local source file deletion flag ("yes" or "no")
#:   $6         [Optional] Contextual tracking suffix or explicit bucket name for "ad-hoc" mode
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/datastore/operations/ResolveBucketName.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/datastore/operations/<DATASTORETOOL>/PerformPutToDatastore.sh
#:   - External binaries: cat, echo, grep, cut, date, dirname, mkdir, awk, tr, wc, rm
#:
#: Exit Codes:
#:   0          Local payload uploaded cleanly across local or distributed datastore endpoints
#:   1          Missing /home/homedir.dat, missing arguments, invalid mode, or missing/failed driver scripts
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

log_error()
{
        error_msg="[$(/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: ${1}"
        /bin/echo "${error_msg}" >&2
        
        if [ -w "${LOG_FILE}" ] || [ -w "$(/usr/bin/dirname "${LOG_FILE}")" ]
        then
                /bin/echo "${error_msg}" >> "${LOG_FILE}"
        fi
}

if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ] || [ -z "${5}" ]
then
        log_error "5 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <bucket_type> <file_to_put> <place_to_put> <mode> <delete> [additional_specifier]" >&2
        exit 1
fi

bucket_type="${1}"
file_to_put="${2}"
place_to_put="${3}"
mode="${4}"
delete="${5}"
additional_specifier="${6}"

resolver_script="${HOME}/services/datastore/operations/ResolveBucketName.sh"
if [ ! -f "${resolver_script}" ] || [ ! -x "${resolver_script}" ]
then
        status "Error: Bucket resolver script missing or not executable at ${resolver_script}"
        exit 1
fi

active_bucket="$("${resolver_script}" "${bucket_type}" "${additional_specifier}")"

DATASTORE_TOOL="$("${HOME}/utilities/config/ExtractBuildStyleValues.sh" "DATASTORETOOL" | /usr/bin/awk -F':' '{print $2}')"
S3_ACCESS_KEY="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'S3ACCESSKEY')"

no_tokens="$(/bin/echo "${S3_ACCESS_KEY}" | /usr/bin/fgrep -o '|' | /usr/bin/wc -l)"
no_tokens="$(/usr/bin/expr "${no_tokens}" + 1)"

count="1"
execution_driver="${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformPutToDatastore.sh"

if [ "${mode}" = "local" ]
then
        "${execution_driver}" "${file_to_put}" "${active_bucket}/${place_to_put}" "${delete}" "${count}"
elif [ "${mode}" = "distributed" ]
then
        while [ "${count}" -le "${no_tokens}" ]
        do
                "${execution_driver}" "${file_to_put}" "${active_bucket}/${place_to_put}" "no" "${count}"
                count="$(/usr/bin/expr "${count}" + 1)"
        done
else
        log_error "Invalid routine mode '${mode}'. Must be 'local' or 'distributed'."
        exit 1
fi

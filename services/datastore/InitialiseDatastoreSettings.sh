#!/bin/sh
#: Name:        InitialiseDatastoreSettings.sh
#: Purpose:     Initialises S3 datastore credentials and provider configuration profiles across all configured endpoints.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialiseDatastoreSettings.sh [multi_region_rclone]
#:              InitialiseDatastoreSettings.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Optional] Multi-region rclone flag passed through to PerformInitialiseDatastoreSettings.sh
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat if unset
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/datastore/PerformInitialiseDatastoreSettings.sh
#:   - External binaries: cat, echo, grep, cut, tr, wc
#:
#: Exit Codes:
#:   0          All datastore credential profiles initialised cleanly
#:   1          Missing /home/homedir.dat, missing S3 credentials, or driver execution failure
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
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: Resolved HOME directory '${HOME}' is invalid." >&2
        exit 1
fi

multi_region_rclone="${1}"

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
if [ ! -x "${config_extractor}" ]
then
        /bin/echo "Error: Configuration extraction helper missing or not executable at ${config_extractor}" >&2
        exit 1
fi

set +e
S3_ACCESS_KEY="$("${config_extractor}" 'S3ACCESSKEY')"
S3_SECRET_KEY="$("${config_extractor}" 'S3SECRETKEY')"
S3_LOCATION="$("${config_extractor}" 'S3LOCATION')"
S3_HOST_BASE="$("${config_extractor}" 'S3HOSTBASE')"
set -e

if [ -z "${S3_ACCESS_KEY}" ] || [ -z "${S3_SECRET_KEY}" ] || [ -z "${S3_HOST_BASE}" ]
then
        /bin/echo "Error: Required S3 configuration values (S3ACCESSKEY, S3SECRETKEY, S3HOSTBASE) are missing." >&2
        exit 1
fi

perform_script="${HOME}/services/datastore/PerformInitialiseDatastoreSettings.sh"
if [ ! -x "${perform_script}" ]
then
        /bin/echo "Error: Datastore initialisation driver missing or not executable at ${perform_script}" >&2
        exit 1
fi

pipe_count="$(/bin/echo "${S3_ACCESS_KEY}" | /usr/bin/tr -cd '|' | /usr/bin/wc -c)"
no_tokens=$((pipe_count + 1))
count=1

while [ "${count}" -le "${no_tokens}" ]
do
        access_key="$(/bin/echo "${S3_ACCESS_KEY}" | /usr/bin/cut -d '|' -f "${count}")"
        secret_key="$(/bin/echo "${S3_SECRET_KEY}" | /usr/bin/cut -d '|' -f "${count}")"
        location="$(/bin/echo "${S3_LOCATION}" | /usr/bin/cut -d '|' -f "${count}")"
        host_base="$(/bin/echo "${S3_HOST_BASE}" | /usr/bin/cut -d '|' -f "${count}")"

        if [ -z "${access_key}" ] || [ -z "${secret_key}" ] || [ -z "${host_base}" ]
        then
                /bin/echo "Error: Incomplete S3 credentials or host_base for datastore endpoint ${count}." >&2
                exit 1
        fi

        if ! "${perform_script}" "${access_key}" "${secret_key}" "${location}" "${host_base}" "${count}" "${multi_region_rclone}"
        then
                /bin/echo "Error: PerformInitialiseDatastoreSettings.sh failed for datastore endpoint ${count}." >&2
                exit 1
        fi

        count=$((count + 1))
done

exit 0



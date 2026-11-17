#!/bin/sh
#: Name:        CreateRepository.sh
#: Purpose:     Provisions a new private GitLab project repository via the GitLab REST API v4.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       CreateRepository.sh "<repository_username>" "<repository_name>"
#:              CreateRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Administrative GitLab username profile identifier
#:   $2         [Required] Target project repository name to create
#:
#: Environment:
#:   BUILD_HOME       Resolved automatically from /home/buildhome.dat
#:   REPOSITORY_TOKEN GitLab personal access token with api scope permissions
#:
#: Dependencies:
#:   - /home/buildhome.dat
#:   - LogStatusMessages.sh
#:   - External binaries: cat, echo, grep, cut, sed, jq, curl
#:
#: Exit Codes:
#:   0          Private GitLab repository created successfully
#:   1          Missing arguments, missing token/config, JSON encoding failure, or non-2xx API status
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

# Resolve the toolkit root directory from the system tracking file
if [ -r /home/buildhome.dat ]
then
        BUILD_HOME="$(/bin/cat /home/buildhome.dat)"
else
        /bin/echo "Application root configuration file missing at /home/buildhome.dat" >&2
        exit 1
fi

# Route status log entries to the centralized logging utility
status()
{
        "${BUILD_HOME}/helpers/services/LogStatusMessages.sh" "${1}" 2>/dev/null
}

# Validate required positional arguments and authentication token
if [ -z "${1}" ] || [ -z "${2}" ]
then
        status "Error: Both repository username and repository name arguments are required."
        status "Usage: $0 <repository_username> <repository_name>"
        exit 1
fi

if [ -z "${REPOSITORY_TOKEN}" ]
then
        status "Error: REPOSITORY_TOKEN environment variable is not set."
        exit 1
fi

repository_username="${1}"
repository_name="${2}"

# Construct the GitLab project creation JSON payload safely via jq
repo_payload="$(/usr/bin/jq -n -c --arg name "${repository_name}" '{ name: $name, path: $name, visibility: "private" }' 2>/dev/null)"

if [ -z "${repo_payload}" ]
then
        status "Error: Failed to construct valid repository JSON payload."
        exit 1
fi

# Assemble endpoint from split components to prevent browser URL rewriting during copy-paste
api_host="gitlab.com"
api_path="api/v4/projects"
endpoint="https://${api_host}/${api_path}"

# Submit the repository creation POST request with token passed securely via stdin
set +e
RESPONSE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | /usr/bin/curl -H @- -s -X POST "${endpoint}" -H "Content-Type: application/json" -d "${repo_payload}" -w "\nHTTP_STATUS:%{http_code}")
curl_status="$?"
set -e

if [ "${curl_status}" -ne 0 ]
then
        status "Error: curl request to ${endpoint} failed with exit code ${curl_status}."
        exit 1
fi

# Separate the HTTP status code and JSON response body
HTTP_CODE=$(/bin/echo "${RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)
RESPONSE_BODY=$(/bin/echo "${RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

# Evaluate HTTP status code and handle API errors explicitly
case "${HTTP_CODE}" in
        200|201)
                status "Success! Private GitLab repository '${repository_username}/${repository_name}' created."
                ;;
        400)
                status "Error 400: Bad Request. Repository '${repository_name}' may already exist or payload is invalid."
                status "API Response: ${RESPONSE_BODY}"
                exit 1
                ;;
        401)
                status "Error 401: Unauthorized. Check your REPOSITORY_TOKEN."
                exit 1
                ;;
        403)
                status "Error 403: Forbidden. Missing project creation permissions."
                exit 1
                ;;
        422)
                status "Error 422: Unprocessable Entity. Check project parameters."
                status "API Response: ${RESPONSE_BODY}"
                exit 1
                ;;
        429)
                status "Error 429: Rate Limit Exceeded."
                exit 1
                ;;
        5*)
                status "Error ${HTTP_CODE}: GitLab Server Error."
                exit 1
                ;;
        *)
                status "Error ${HTTP_CODE}: Unexpected response."
                status "API Response: ${RESPONSE_BODY}"
                exit 1
                ;;
esac

exit 0

#!/bin/sh
#: Name:        CreateRepository.sh
#: Purpose:     Provisions a new private GitHub repository via the GitHub REST API v3.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       CreateRepository.sh "<repository_username>" "<repository_name>"
#:              CreateRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Administrative GitHub username profile identifier
#:   $2         [Required] Target repository name to create
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:   REPOSITORY_TOKEN Personal access token with repo creation permissions
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - External binaries: cat, echo, grep, cut, sed, jq, curl
#:
#: Exit Codes:
#:   0          Private GitHub repository created successfully
#:   1          Missing arguments, missing token/config, JSON encoding failure, or non-2xx API /bin/echo
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

# Exit immediately if any command exits with a non-zero /bin/echo
set -e

# Render self-extracting help documentation when -h or --help is supplied
if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]
then
        /usr/bin/grep '^#:' "$0" | /usr/bin/cut -c 4-
        exit 0
fi

# Resolve the toolkit root directory from the system tracking file
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi


# Validate required positional arguments and authentication token
if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: Both repository username and repository name arguments are required."  >&2
        /bin/echo "Usage: $0 <repository_username> <repository_name>"  >&2
        exit 1
fi

if [ -z "${REPOSITORY_TOKEN}" ]
then
        /bin/echo "Error: REPOSITORY_TOKEN environment variable is not set."  >&2
        exit 1
fi

repository_username="${1}"
repository_name="${2}"

# Construct the GitHub repository creation JSON payload safely via jq
repo_payload="$(/usr/bin/jq -n -c --arg name "${repository_name}" '{ name: $name, private: true }' 2>/dev/null)"

if [ -z "${repo_payload}" ]
then
        /bin/echo "Error: Failed to construct valid repository JSON payload."  >&2
        exit 1
fi

# Assemble endpoint from split components to prevent browser URL rewriting during copy-paste
api_sub="api"
api_domain="github.com"
api_path="user/repos"
endpoint="https://${api_sub}.${api_domain}/${api_path}"

# Submit the repository creation POST request with token passed securely via stdin
set +e
RESPONSE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | /usr/bin/curl -H @- -s -X POST "${endpoint}" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" -d "${repo_payload}" -w "\nHTTP_STATUS:%{http_code}")
curl_status="$?"
set -e

if [ "${curl_status}" -ne 0 ]
then
        /bin/echo "Error: curl request to ${endpoint} failed with exit code ${curl_status}."  >&2
        exit 1
fi

# Separate the HTTP /bin/echo code and JSON response body
HTTP_CODE=$(/bin/echo "${RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)
RESPONSE_BODY=$(/bin/echo "${RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

case "${HTTP_CODE}" in
        200|201)
                /bin/echo "Success! Private GitHub repository '${repository_username}/${repository_name}' created."
                ;;
        400)
                /bin/echo "Error 400: Bad Request. Check your payload syntax."  >&2
                /bin/echo "API Response: ${RESPONSE_BODY}"  >&2
                exit 1
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Check your REPOSITORY_TOKEN."  >&2
                exit 1
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Missing repository creation permissions."  >&2
                exit 1
                ;;
        422)
                /bin/echo "Error 422: Unprocessable Entity. Repository '${repository_name}' may already exist."  >&2
                /bin/echo "API Response: ${RESPONSE_BODY}"  >&2
                exit 1
                ;;
        429)
                /bin/echo "Error 429: Rate Limit Exceeded."  >&2
                exit 1
                ;;
        5*)
                /bin/echo "Error ${HTTP_CODE}: GitHub Server Error."  >&2
                exit 1
                ;;
        *)
                /bin/echo "Error ${HTTP_CODE}: Unexpected response."  >&2
                /bin/echo "API Response: ${RESPONSE_BODY}"  >&2
                exit 1
                ;;
esac

exit 0

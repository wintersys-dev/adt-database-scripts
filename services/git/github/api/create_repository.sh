#!/bin/sh
#: Name:        create_repository.sh
#: Purpose:     Creates a new private Bitbucket Git repository via REST API using netrc stdin.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       create_repository.sh <repository_username> <repository_name>
#:
#: Parameters:
#:   $1         [Required] The Bitbucket workspace or repository username.
#:   $2         [Required] The name/slug of the repository to create.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: cat, curl, cut, echo, grep, sed
#:
#: Exit Codes:
#:   0          Repository created cleanly via API (HTTP 200/201)
#:   1          Missing arguments, layout faults, missing credentials, or unexpected HTTP code
#:   400        Bad Request (repository already exists or invalid payload syntax)
#:   401        Unauthorized (invalid or expired APPLICATIONREPOSITORYTOKEN or email)
#:   403        Forbidden (token lacks repository creation permissions in workspace)
#:   404        Not Found (target workspace or user does not exist)
#:   429        Rate Limit Exceeded
#:   500        Bitbucket Gateway or Remote Server Exception (5xx)
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

set -e

if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: Repository username and repository name arguments are required." >&2
        /bin/echo "Usage: $0 <repository_username> <repository_name>" >&2
        exit 1
fi

repository_username="${1}"
repository_name="${2}"

set +e
REPOSITORY_TOKEN="$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYTOKEN')"
ATLASSIAN_EMAIL="$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYEMAIL')"
set -e

if [ -z "${REPOSITORY_TOKEN}" ] || [ -z "${ATLASSIAN_EMAIL}" ]
then
        /bin/echo "Error: Failed to fetch required context variables (APPLICATIONREPOSITORYTOKEN or APPLICATIONREPOSITORYEMAIL)." >&2
        exit 1
fi

# Build the full API endpoint and JSON payload beforehand
api_base="https://api.bitbucket.org/2.0"
endpoint_url="${api_base}/repositories/${repository_username}/${repository_name}"
payload='{"scm": "git", "is_private": true, "fork_policy": "no_public_forks"}'

set +e
# Pipe netrc credentials via /dev/stdin to prevent disk writes or exposure in process trees
RESPONSE=$(/bin/echo "machine api.bitbucket.org login ${ATLASSIAN_EMAIL} password ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -X POST --netrc-file /dev/stdin \
        -H "Content-Type: application/json" \
        "${endpoint_url}" \
        -d "${payload}" \
        -w "\nHTTP_STATUS:%{http_code}")
set -e

# Extract the HTTP status code using strict POSIX filtering
HTTP_CODE=$(/bin/echo "${RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)

# Extract the raw response body by dropping the status delimiter line
RESPONSE_BODY=$(/bin/echo "${RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

# Evaluate the API response code using strict POSIX structural matching
case "${HTTP_CODE}" in
        200|201)
                /bin/echo "${RESPONSE_BODY}"
                exit 0
                ;;
        400)
                /bin/echo "Error 400: Bad Request. Repository may already exist or payload syntax is invalid." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 400
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Your REPOSITORY_TOKEN or ATLASSIAN_EMAIL is invalid or has expired." >&2
                exit 401
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Token lacks permissions to create repositories in this workspace." >&2
                exit 403
                ;;
        404)
                /bin/echo "Error 404: Not Found. The target workspace or user (${repository_username}) does not exist." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 404
                ;;
        429)
                /bin/echo "Error 429: Rate Limit Exceeded. Back off request frequency." >&2
                exit 429
                ;;
        5*)
                /bin/echo "Error ${HTTP_CODE}: Bitbucket Gateway or Remote Server Exception." >&2
                exit 500
                ;;
        *)
                /bin/echo "Error ${HTTP_CODE}: Remote endpoint refused connection or threw an unexpected code." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 1
                ;;
esac

exit 0

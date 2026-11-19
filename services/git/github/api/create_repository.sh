#!/bin/sh
#: Name:        create_repository.sh
#: Purpose:     Creates a new private GitHub repository via REST API using Bearer stdin.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       create_repository.sh <repository_owner> <repository_name>
#:
#: Parameters:
#:   $1         [Required] The GitHub username or organization name (repository owner).
#:   $2         [Required] The name/slug of the repository to create.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: cat, curl, cut, echo, grep, jq, sed
#:
#: Exit Codes:
#:   0          Repository created cleanly via API (HTTP 201)
#:   1          Missing arguments, layout faults, missing credentials, or unexpected HTTP code
#:   401        Unauthorized (invalid or expired APPLICATIONREPOSITORYTOKEN)
#:   403        Forbidden (token lacks repository creation permissions)
#:   404        Not Found (target organization or user does not exist)
#:   422        Unprocessable Entity (repository already exists or invalid name)
#:   429        Rate Limit Exceeded
#:   500        GitHub Gateway or Remote Server Exception (5xx)
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

#set -x
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
        /bin/echo "Error: Repository owner and repository name arguments are required." >&2
        /bin/echo "Usage: $0 <repository_owner> <repository_name>" >&2
        exit 1
fi

repository_owner="${1}"
repository_name="${2}"

set +e
REPOSITORY_TOKEN="$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYTOKEN')"
set -e

if [ -z "${REPOSITORY_TOKEN}" ]
then
        /bin/echo "Error: Failed to fetch required context variables (APPLICATIONREPOSITORYTOKEN)." >&2
        exit 1
fi

github_api_version="2026-03-10"
api_base="https://api.github.com"

# Determine whether repository_owner is the authenticated user or an organization
set +e
auth_user="$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -H @- \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        "${api_base}/user" | /usr/bin/jq -r '.login // empty')"
set -e

if [ "${auth_user}" = "${repository_owner}" ]
then
        endpoint_url="${api_base}/user/repos"
else
        endpoint_url="${api_base}/orgs/${repository_owner}/repos"
fi

payload="{\"name\": \"${repository_name}\", \"private\": true}"

set +e
RESPONSE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -X POST -H @- \
        -H "Accept: application/vnd.github+json" \
        -H "Content-Type: application/json" \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        "${endpoint_url}" \
        -d "${payload}" \
        -w "\nHTTP_STATUS:%{http_code}")
set -e

HTTP_CODE=$(/bin/echo "${RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)
RESPONSE_BODY=$(/bin/echo "${RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

case "${HTTP_CODE}" in
        200|201)
                /bin/echo "${RESPONSE_BODY}"
                exit 0
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Your APPLICATIONREPOSITORYTOKEN is invalid or has expired." >&2
                exit 401
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Token lacks permissions to create repositories under ${repository_owner}." >&2
                exit 403
                ;;
        404)
                /bin/echo "Error 404: Not Found. Target organization or user (${repository_owner}) does not exist." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 404
                ;;
        422)
                /bin/echo "Error 422: Unprocessable Entity. Repository '${repository_name}' may already exist or name is invalid." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 422
                ;;
        429)
                /bin/echo "Error 429: Rate Limit Exceeded. Back off request frequency." >&2
                exit 429
                ;;
        5*)
                /bin/echo "Error ${HTTP_CODE}: GitHub Gateway or Remote Server Exception." >&2
                exit 500
                ;;
        *)
                /bin/echo "Error ${HTTP_CODE}: Remote endpoint refused connection or threw an unexpected code." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 1
                ;;
esac

exit 0

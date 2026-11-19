#!/bin/sh
#: Name:        create_repository.sh
#: Purpose:     Creates a new private GitLab project via REST API v4 using header stdin.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       create_repository.sh <repository_owner> <repository_name>
#:
#: Parameters:
#:   $1         [Required] The GitLab username or group path (repository owner).
#:   $2         [Required] The name/slug of the project to create.
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
#:   0          Project created cleanly via API (HTTP 200/201)
#:   1          Missing arguments, layout faults, missing credentials, or unexpected HTTP code
#:   400        Bad Request (project already exists or invalid payload syntax)
#:   401        Unauthorized (invalid or expired APPLICATIONREPOSITORYTOKEN)
#:   403        Forbidden (token lacks permissions to create projects under target owner)
#:   404        Not Found (target group or namespace does not exist)
#:   429        Rate Limit Exceeded
#:   500        GitLab Gateway or Remote Server Exception (5xx)
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

api_base="https://gitlab.com/api/v4"
endpoint_url="${api_base}/projects"

# Determine whether repository_owner is the authenticated user or a GitLab group
set +e
auth_user="$(/bin/echo "PRIVATE-TOKEN: ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -H @- \
        "${api_base}/user" | /usr/bin/jq -r '.username // empty')"
set -e

if [ "${auth_user}" = "${repository_owner}" ]
then
        payload="{\"name\": \"${repository_name}\", \"path\": \"${repository_name}\", \"visibility\": \"private\"}"
else
        # URL-encode slashes for sub-groups (e.g. parent/subgroup -> parent%2Fsubgroup)
        encoded_group="$(/bin/echo "${repository_owner}" | /usr/bin/sed 's/\//%2F/g')"
        set +e
        namespace_id="$(/bin/echo "PRIVATE-TOKEN: ${REPOSITORY_TOKEN}" | \
                /usr/bin/curl -s -H @- \
                "${api_base}/groups/${encoded_group}" | /usr/bin/jq -r '.id // empty')"
        set -e

        if [ -z "${namespace_id}" ]
        then
                /bin/echo "Error 404: Not Found. Target GitLab group or namespace (${repository_owner}) could not be resolved." >&2
                exit 404
        fi

        payload="{\"name\": \"${repository_name}\", \"path\": \"${repository_name}\", \"namespace_id\": ${namespace_id}, \"visibility\": \"private\"}"
fi

set +e
RESPONSE=$(/bin/echo "PRIVATE-TOKEN: ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -X POST -H @- \
        -H "Content-Type: application/json" \
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
        400)
                /bin/echo "Error 400: Bad Request. Project '${repository_name}' may already exist or payload syntax is invalid." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 400
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Your APPLICATIONREPOSITORYTOKEN is invalid or has expired." >&2
                exit 401
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Token lacks permissions to create projects under ${repository_owner}." >&2
                exit 403
                ;;
        404)
                /bin/echo "Error 404: Not Found. Target group or user (${repository_owner}) does not exist." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 404
                ;;
        429)
                /bin/echo "Error 429: Rate Limit Exceeded. Back off request frequency." >&2
                exit 429
                ;;
        5*)
                /bin/echo "Error ${HTTP_CODE}: GitLab Gateway or Remote Server Exception." >&2
                exit 500
                ;;
        *)
                /bin/echo "Error ${HTTP_CODE}: Remote endpoint refused connection or threw an unexpected code." >&2
                /bin/echo "API Detail: ${RESPONSE_BODY}" >&2
                exit 1
                ;;
esac

exit 0

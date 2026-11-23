#!/bin/sh
#: Name:        list_repository.sh
#: Purpose:     Checks a GitHub repository state ("full", "empty", or "none") via REST API.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       list_repository.sh <repository_name> <repository_ownername>
#:              list_repository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the repository to inspect.
#:   $2         [Required] The GitHub organisation or account owner name.
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
#:   0          Repository state ("full", "empty", or "none") printed to stdout
#:   1          Missing arguments, layout faults, missing credentials, or unexpected HTTP code
#:   401        Unauthorized (invalid or expired APPLICATIONREPOSITORYTOKEN)
#:   403        Forbidden (token lacks permissions to inspect target repository)
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

if [ "${1}" = "-h" ] || [ "${1}" = "--help" ]
then
        /usr/bin/grep '^#:' "$0" | /usr/bin/cut -c 4-
        exit 0
fi

if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: Repository name and repository owner name arguments are required." >&2
        /bin/echo "Usage: $0 <repository_name> <repository_ownername> " >&2
        exit 1
fi

repository_name="${1}"
repository_ownername="${2}"

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
repo_endpoint="${api_base}/repos/${repository_ownername}/${repository_name}"
commits_endpoint="${repo_endpoint}/commits?per_page=1"

set +e
REPO_RESPONSE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -H @- \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        "${repo_endpoint}" \
        -w "\nHTTP_STATUS:%{http_code}")
set -e

REPO_HTTP_CODE=$(/bin/echo "${REPO_RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)
REPO_BODY=$(/bin/echo "${REPO_RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

case "${REPO_HTTP_CODE}" in
        200)
                ;;
        404)
                /bin/echo "none"
                exit 0
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Your APPLICATIONREPOSITORYTOKEN is invalid or has expired." >&2
                exit 401
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Token lacks permissions to inspect ${repository_ownername}/${repository_name}." >&2
                exit 403
                ;;
        429)
                /bin/echo "Error 429: Rate Limit Exceeded. Back off request frequency." >&2
                exit 429
                ;;
        5*)
                /bin/echo "Error ${REPO_HTTP_CODE}: GitHub Gateway or Remote Server Exception." >&2
                exit 500
                ;;
        *)
                /bin/echo "Error ${REPO_HTTP_CODE}: Remote endpoint refused connection or threw an unexpected code." >&2
                /bin/echo "API Detail: ${REPO_BODY}" >&2
                exit 1
                ;;
esac

set +e
COMMITS_RESPONSE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -H @- \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        "${commits_endpoint}" \
        -w "\nHTTP_STATUS:%{http_code}")
set -e

COMMITS_HTTP_CODE=$(/bin/echo "${COMMITS_RESPONSE}" | /usr/bin/grep "HTTP_STATUS:" | /usr/bin/cut -d':' -f2)
COMMITS_BODY=$(/bin/echo "${COMMITS_RESPONSE}" | /usr/bin/sed '/HTTP_STATUS:/d')

case "${COMMITS_HTTP_CODE}" in
        200)
                commit_count="$(/bin/echo "${COMMITS_BODY}" | /usr/bin/jq 'length' 2>/dev/null)"
                if [ -n "${commit_count}" ] && [ "${commit_count}" -gt 0 ]
                then
                        /bin/echo "full"
                else
                        /bin/echo "empty"
                fi
                exit 0
                ;;
        409)
                # GitHub returns HTTP 409 ("Git Repository is empty") when querying /commits on a repo with 0 commits
                /bin/echo "empty"
                exit 0
                ;;
        *)
                /bin/echo "Error ${COMMITS_HTTP_CODE}: Unexpected response querying repository commits." >&2
                /bin/echo "API Detail: ${COMMITS_BODY}" >&2
                exit 1
                ;;
esac

exit 0

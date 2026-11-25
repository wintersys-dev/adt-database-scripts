#!/bin/sh
#: Name:        list_repository.sh
#: Purpose:     Checks a GitHub repository state ("full", "empty", or "none") via REST API (public first, authenticated fallback).
#: Author:      Peter Winter
#: Date:        25/11/2026
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
#:   - External binaries: cat, curl, cut, echo, grep, jq, mktemp, printf, rm
#:
#: Exit Codes:
#:   0          Repository state ("full", "empty", or "none") printed to stdout
#:   1          Missing arguments, layout faults, connection error, or unexpected HTTP code
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
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

repository_name="${1}"
repository_ownername="${2}"

if [ -z "${repository_name}" ] || [ -z "${repository_ownername}" ]
then
        /bin/echo "Error: Repository name and repository ownername arguments are required." >&2
        /bin/echo "Usage: $0 <repository_name> <repository_ownername>" >&2
        exit 1
fi

tmp_response="$(/bin/mktemp /tmp/gh_repo_list.XXXXXX.json)"

cleanup() {
        /bin/rm -f "${tmp_response}"
}
trap cleanup EXIT INT TERM

api_base="https://api.github.com"
repo_endpoint="${api_base}/repos/${repository_ownername}/${repository_name}"
commits_endpoint="${repo_endpoint}/commits?per_page=1"

# 1. Attempt unauthenticated repository lookup first (works for public repos without touching credentials)
set +e
REPO_HTTP_CODE=$(/usr/bin/curl -s --connect-timeout 15 \
        -H "Accept: application/vnd.github+json" \
        -o "${tmp_response}" \
        -w "%{http_code}" \
        "${repo_endpoint}")
set -e

USE_AUTH=0

# 2. If public access fails (e.g., 404 on a private repo, or 403/429 unauthenticated rate limit), retry with Bearer token
if [ "${REPO_HTTP_CODE}" != "200" ]
then
        set +e
        REPOSITORY_TOKEN="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYTOKEN' 2>/dev/null)"
        set -e

        if [ -n "${REPOSITORY_TOKEN}" ] && [ "${REPOSITORY_TOKEN}" != "none" ]
        then
                USE_AUTH=1
                : > "${tmp_response}"
                set +e
                REPO_HTTP_CODE=$(/usr/bin/printf 'Authorization: Bearer %s\n' "${REPOSITORY_TOKEN}" | \
                        /usr/bin/curl -s --connect-timeout 15 -H @- \
                        -H "Accept: application/vnd.github+json" \
                        -o "${tmp_response}" \
                        -w "%{http_code}" \
                        "${repo_endpoint}")
                set -e
        fi
fi

case "${REPO_HTTP_CODE}" in
        000)
                unset REPOSITORY_TOKEN
                /bin/echo "Error 000: Connection failed or timed out while reaching ://github.com." >&2
                exit 1
                ;;
        200)
                ;;
        404)
                unset REPOSITORY_TOKEN
                /bin/echo "none"
                exit 0
                ;;
        401)
                unset REPOSITORY_TOKEN
                /bin/echo "Error 401: Unauthorized. Your APPLICATIONREPOSITORYTOKEN is invalid or has expired." >&2
                exit 401
                ;;
        403)
                unset REPOSITORY_TOKEN
                /bin/echo "Error 403: Forbidden. Token lacks permissions or rate limit exceeded for ${repository_ownername}/${repository_name}." >&2
                exit 403
                ;;
        429)
                unset REPOSITORY_TOKEN
                /bin/echo "Error 429: Rate Limit Exceeded. Back off request frequency." >&2
                exit 429
                ;;
        5*)
                unset REPOSITORY_TOKEN
                /bin/echo "Error ${REPO_HTTP_CODE}: GitHub Gateway or Remote Server Exception." >&2
                exit 500
                ;;
        *)
                REPO_BODY="$(/bin/cat "${tmp_response}" 2>/dev/null)"
                unset REPOSITORY_TOKEN
                /bin/echo "Error ${REPO_HTTP_CODE}: Remote endpoint refused connection or threw an unexpected code." >&2
                /bin/echo "API Detail: ${REPO_BODY}" >&2
                exit 1
                ;;
esac

# 3. Query /commits using the same auth mode that succeeded for the repository metadata
: > "${tmp_response}"
if [ "${USE_AUTH}" -eq 1 ]
then
        set +e
        COMMITS_HTTP_CODE=$(/usr/bin/printf 'Authorization: Bearer %s\n' "${REPOSITORY_TOKEN}" | \
                /usr/bin/curl -s --connect-timeout 15 -H @- \
                -H "Accept: application/vnd.github+json" \
                -o "${tmp_response}" \
                -w "%{http_code}" \
                "${commits_endpoint}")
        set -e
else
        set +e
        COMMITS_HTTP_CODE=$(/usr/bin/curl -s --connect-timeout 15 \
                -H "Accept: application/vnd.github+json" \
                -o "${tmp_response}" \
                -w "%{http_code}" \
                "${commits_endpoint}")
        set -e
fi

unset REPOSITORY_TOKEN

case "${COMMITS_HTTP_CODE}" in
        000)
                /bin/echo "Error 000: Connection failed or timed out while querying repository commits." >&2
                exit 1
                ;;
        200)
                commit_count="$(/usr/bin/jq 'length' "${tmp_response}" 2>/dev/null)"
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
                COMMITS_BODY="$(/bin/cat "${tmp_response}" 2>/dev/null)"
                /bin/echo "Error ${COMMITS_HTTP_CODE}: Unexpected response querying repository commits." >&2
                /bin/echo "API Detail: ${COMMITS_BODY}" >&2
                exit 1
                ;;
esac

exit 0

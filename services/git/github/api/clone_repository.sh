#!/bin/sh
#: Name:        clone_repository.sh
#: Purpose:     Downloads and extracts a GitHub repository branch tarball via REST API (public first, authenticated fallback).
#: Author:      Peter Winter
#: Date:        22/11/2026
#: Version:     1.0
#:
#: Usage:       clone_repository.sh <repository_name> <branch> <destination_directory> <repository_ownername>
#:              clone_repository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the GitHub repository to download.
#:   $2         [Required] Target branch name.
#:   $3         [Required] Local destination directory for the extracted files.
#:   $4         [Required] The GitHub organisation or account owner name.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: cat, curl, cut, echo, grep, mkdir, mktemp, printf, rm, tar
#:
#: Exit Codes:
#:   0          Repository archive downloaded and extracted cleanly
#:   1          Missing arguments, layout faults, extraction error, or unexpected HTTP code
#:   401        Unauthorized (invalid or expired APPLICATIONREPOSITORYTOKEN)
#:   403        Forbidden (token lacks read permissions for target repository)
#:   404        Not Found (repository or branch does not exist)
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
branch="${2}"
destination_directory="${3}"
repository_ownername="${4}"

if [ -z "${repository_name}" ] || [ -z "${branch}" ] || [ -z "${destination_directory}" ] || [ -z "${repository_ownername}" ]
then
        /bin/echo "Error: Repository name, branch, destination directory, and repository owner are required." >&2
        /bin/echo "Usage: $0 <repository_name> <branch> <destination_directory> <repository_ownername>" >&2
        exit 1
fi

tmp_archive="$(/bin/mktemp /tmp/repo_archive.XXXXXX.tar.gz)"

cleanup() {
        /bin/rm -f "${tmp_archive}"
}
trap cleanup EXIT INT TERM

api_base="https://api.github.com"
endpoint_url="${api_base}/repos/${repository_ownername}/${repository_name}/tarball/${branch}"

# 1. Attempt unauthenticated download first (works for public repositories without touching credentials)
set +e
HTTP_CODE=$(/usr/bin/curl -s -L --connect-timeout 15 \
        -H "Accept: application/vnd.github+json" \
        -o "${tmp_archive}" \
        -w "%{http_code}" \
        "${endpoint_url}")
set -e

# 2. If public access fails (e.g., 404/403/401 on a private repository), retry with Bearer token
if [ "${HTTP_CODE}" != "200" ]
then
        set +e
        REPOSITORY_TOKEN="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYTOKEN' 2>/dev/null)"
        set -e

        if [ -n "${REPOSITORY_TOKEN}" ] && [ "${REPOSITORY_TOKEN}" != "none" ]
        then
                /bin/rm -f "${tmp_archive}"
                set +e
                HTTP_CODE=$(/usr/bin/printf 'Authorization: Bearer %s\n' "${REPOSITORY_TOKEN}" | \
                        /usr/bin/curl -s -L --connect-timeout 15 -H @- \
                        -H "Accept: application/vnd.github+json" \
                        -o "${tmp_archive}" \
                        -w "%{http_code}" \
                        "${endpoint_url}")
                set -e
        fi

        unset REPOSITORY_TOKEN
fi

case "${HTTP_CODE}" in
        000)
                /bin/echo "Error 000: Connection failed or timed out while reaching ://github.com." >&2
                exit 1
                ;;
        200)
                /bin/mkdir -p "${destination_directory}"
                set +e
                /bin/tar -xzf "${tmp_archive}" -C "${destination_directory}" --strip-components=1 >&2
                tar_status="$?"
                set -e

                if [ "${tar_status}" -ne 0 ]
                then
                        /bin/echo "Error: Failed to extract repository archive into ${destination_directory}." >&2
                        exit 1
                fi

                /bin/echo "${destination_directory}"
                exit 0
                ;;
        401)
                /bin/echo "Error 401: Unauthorized. Your APPLICATIONREPOSITORYTOKEN is invalid or has expired." >&2
                exit 401
                ;;
        403)
                /bin/echo "Error 403: Forbidden. Token lacks read permissions for ${repository_ownername}/${repository_name}." >&2
                exit 403
                ;;
        404)
                /bin/echo "Error 404: Not Found. Repository ${repository_ownername}/${repository_name} or branch '${branch}' does not exist." >&2
                exit 404
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
                exit 1
                ;;
esac

exit 0

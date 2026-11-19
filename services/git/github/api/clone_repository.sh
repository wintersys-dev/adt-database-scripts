#!/bin/sh
#: Name:        clone_repository.sh
#: Purpose:     Downloads and extracts a GitHub repository branch archive via REST API.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       clone_repository.sh <branch> <repository_ownername> <repository_name> <destination_directory>
#:              clone_repository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Target branch name or "--branch <name>" flag.
#:   $2         [Required] GitHub organisation or individual account namespace.
#:   $3         [Required] Case-sensitive name of the target GitHub repository.
#:   $4         [Required] Local destination directory for the extracted files.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: cat, curl, cut, echo, find, grep, mkdir, mktemp, rm, sed, tar, xargs
#:
#: Exit Codes:
#:   0          Repository archive downloaded, extracted, and normalised to LF cleanly
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
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ]
then
        /bin/echo "Error: Branch, repository owner, repository name, and destination directory are required." >&2
        /bin/echo "Usage: $0 <branch> <repository_ownername> <repository_name> <destination_directory>" >&2
        exit 1
fi

branch="$(/bin/echo "${1}" | /usr/bin/sed 's/^--branch[[:space:]]*//')"
repository_ownername="${2}"
repository_name="${3}"
destination_directory="${4}"

set +e
REPOSITORY_TOKEN="$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYTOKEN')"
set -e

if [ -z "${REPOSITORY_TOKEN}" ]
then
        /bin/echo "Error: Failed to fetch required context variables (APPLICATIONREPOSITORYTOKEN)." >&2
        exit 1
fi

tmp_archive="$(/bin/mktemp /tmp/repo_archive.XXXXXX.tar.gz)"

cleanup() {
        /bin/rm -f "${tmp_archive}"
}
trap cleanup EXIT INT TERM

github_api_version="2026-03-10"
api_base="https://api.github.com"
endpoint_url="${api_base}/repos/${repository_ownername}/${repository_name}/tarball/${branch}"

set +e
HTTP_CODE=$(/bin/echo "Authorization: Bearer ${REPOSITORY_TOKEN}" | \
        /usr/bin/curl -s -L -H @- \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: ${github_api_version}" \
        -o "${tmp_archive}" \
        -w "%{http_code}" \
        "${endpoint_url}")
set -e

case "${HTTP_CODE}" in
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

                # Normalise CRLF (^M) line endings to LF on extracted text files while skipping binary assets
                /usr/bin/find "${destination_directory}" -type f -exec /usr/bin/grep -Il '' {} + | /usr/bin/xargs -r /bin/sed -i 's/\r$//'

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

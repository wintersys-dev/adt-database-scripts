#!/bin/sh
#: Name:        GitLSRemote.sh
#: Purpose:     Probes a remote Bitbucket repository and classifies its state as "full", "empty", or "none".
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       GitLSRemote.sh "<repository_ownername>" "<repository_name>" ["<repository_username>"]
#:              GitLSRemote.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Bitbucket workspace or individual account namespace
#:   $2         [Required] Case-sensitive slug/name of the target Bitbucket repository
#:   $3         [Optional] Bitbucket username associated with REPOSITORY_TOKEN (defaults to x-token-auth)
#:
#: Environment:
#:   HOME             Resolved automatically from /home/homedir.dat
#:   REPOSITORY_TOKEN Optional Bitbucket access token or app password for private repository authentication
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/.netrc (created transiently with mode 600 and removed on exit)
#:   - External binaries: cat, echo, grep, cut, chmod, rm, git
#:
#: Exit Codes:
#:   0          Repository probe completed; emits "full", "empty", or "none" on stdout
#:   1          Missing required arguments or unreadable /home/homedir.dat
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

# Resolve the toolkit root directory from the server tracking file
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

# Validate minimum required positional arguments
if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: 2 arguments are required and 1 optional argument." >&2
        /bin/echo "Usage: $0 <repository_ownername> <repository_name> [repository_username]" >&2
        exit 1
fi

repository_ownername="${1}"
repository_name="${2}"
repository_username="${3}"

# Default to Bitbucket's standard token login identifier if no explicit username was provided
if [ -z "${repository_username}" ]
then
        repository_username="x-token-auth"
fi

# Construct temporary .netrc with restricted permissions and guaranteed cleanup on exit
netrc_file="${HOME}/.netrc"
trap '/bin/rm -f "${netrc_file}"' EXIT

if [ -n "${REPOSITORY_TOKEN}" ]
then
        (
                umask 077
                /bin/cat << EOF > "${netrc_file}"
machine bitbucket.org
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF
        )
        /bin/chmod 600 "${netrc_file}"
fi

# Assemble target Bitbucket repository URL from split components
git_host="bitbucket.org"
repo_url="https://${git_host}/${repository_ownername}/${repository_name}.git"

# Perform non-interactive remote repository lookup and capture exit code safely
set +e
remote_refs="$(GIT_TERMINAL_PROMPT=0 /usr/bin/git ls-remote "${repo_url}" 2>/dev/null)"
error_code="$?"
set -e

if [ "${error_code}" -ne 0 ]
then
        /bin/echo "none"
        exit 0
fi

# Check for a valid 40-character lowercase hex SHA-1 HEAD reference
head_ref="$(printf '%s\n' "${remote_refs}" | /usr/bin/grep -E '^[0-9a-f]{40}[[:space:]]+HEAD$' || true)"

if [ -n "${head_ref}" ]
then
        /bin/echo "full"
else
        /bin/echo "empty"
fi

exit 0


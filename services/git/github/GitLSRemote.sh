#!/bin/sh
#: Name:        GitLSRemote.sh
#: Purpose:     Checks whether a remote Git repository exists and resolves its SHA-1 HEAD reference via git ls-remote.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       GitLSRemote.sh "<repository_provider>" "<repository_ownername>" "<repository_name>" ["<repository_username>"]
#:              GitLSRemote.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Hosting vendor identifier (github, gitlab, bitbucket)
#:   $2         [Required] Organisation, workspace, or individual account namespace
#:   $3         [Required] Case-sensitive target repository name
#:   $4         [Optional] Account username associated with REPOSITORY_TOKEN (auto-resolved if omitted)
#:
#: Environment:
#:   HOME             Resolved automatically from /home/homedir.dat
#:   REPOSITORY_TOKEN Optional access token for private repository authentication
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/.netrc (created transiently with mode 600 and removed on exit)
#:   - External binaries: cat, echo, grep, cut, chmod, rm, git
#:
#: Exit Codes:
#:   0          Remote repository exists and valid 40-char hex HEAD reference emitted on stdout
#:   1          Missing required arguments, unsupported provider, or git ls-remote / HEAD lookup failure
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


if [ -z "${repository_username}" ]
then
        repository_username="${default_user}"
fi

# Construct temporary .netrc with restricted permissions and guaranteed cleanup on exit
netrc_file="${HOME}/.netrc"
trap '/bin/rm -f "${netrc_file}"' EXIT

if [ -n "${REPOSITORY_TOKEN}" ]
then
        (
                umask 077
                /bin/cat << EOF > "${netrc_file}"
machine github.com
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF
)
/bin/chmod 600 "${netrc_file}"
fi

# Assemble target repository URL from split components
repo_url="https://github.com/${repository_ownername}/${repository_name}.git"

# Perform remote repository lookup and capture exit code safely
set +e
remote_refs="$(/usr/bin/git ls-remote "${repo_url}" 2>/dev/null)"
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

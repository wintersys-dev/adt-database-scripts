#!/bin/sh
#: Name:        GitClone.sh
#: Purpose:     Executes a branch-specific shallow Git clone from GitLab with optional scoped .netrc authentication.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       GitClone.sh "<repository_ownername>" "<repository_name>" "<repository_branch>" "<destination_directory>" ["<repository_username>"]
#:              GitClone.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] GitLab group, subgroup path, or individual account namespace
#:   $2         [Required] Case-sensitive name of the target GitLab repository
#:   $3         [Required] Target branch name to clone
#:   $4         [Required] Destination directory path to clone into
#:   $5         [Optional] GitLab username associated with REPOSITORY_TOKEN (defaults to oauth2)
#:
#: Environment:
#:   HOME             Resolved automatically from /home/homedir.dat
#:   REPOSITORY_TOKEN Optional GitLab access token for private repository authentication
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/.netrc (created transiently with mode 600 and removed on exit)
#:   - External binaries: cat, echo, grep, cut, chmod, rm, git
#:
#: Exit Codes:
#:   0          Repository branch cloned successfully from GitLab
#:   1          Missing required arguments, missing config file, or git clone failure
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
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ]
then
        /bin/echo "Error: 4 arguments are required with 1 optional argument." >&2
        /bin/echo "Usage: $0 <repository_ownername> <repository_name> <repository_branch> <destination_directory> [repository_username]" >&2
        exit 1
fi

repository_ownername="${1}"
repository_name="${2}"
repository_branch="${3}"
destination_directory="${4}"
repository_username="${5}"

# Construct temporary .netrc with restricted permissions and guaranteed cleanup on exit
netrc_file="${HOME}/.netrc"
trap '/bin/rm -f "${netrc_file}"' EXIT

if [ -n "${REPOSITORY_TOKEN}" ]
then
        if [ -z "${repository_username}" ]
        then
                repository_username="oauth2"
        fi

        (
                umask 077
                /bin/cat << EOF > "${netrc_file}"
machine gitlab.com
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF
        )
        /bin/chmod 600 "${netrc_file}"
fi

# Assemble GitLab repository URL from split components
git_host="gitlab.com"
repo_url="https://${git_host}/${repository_ownername}/${repository_name}.git"

# Perform branch-specific shallow clone and capture exit code safely
set +e
/usr/bin/git clone --depth 1 --branch "${repository_branch}" "${repo_url}" "${destination_directory}"
error_code="$?"
set -e

/bin/rm -f "${netrc_file}"

if [ "${error_code}" -ne 0 ]
then
        /bin/echo "Error: git clone exited with error code ${error_code}." >&2
        exit 1
fi

exit 0

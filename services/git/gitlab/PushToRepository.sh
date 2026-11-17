#!/bin/sh
#: Name:        PushToRepository.sh
#: Purpose:     Initializes a local Git workspace, commits baseline files, and pushes to a GitLab repository.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       PushToRepository.sh "<repository_owner>" "<repository_name>" ["<repository_username>"]
#:              PushToRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] GitLab group, subgroup path, or individual account namespace
#:   $2         [Required] Case-sensitive target GitLab repository name
#:   $3         [Optional] GitLab username associated with REPOSITORY_TOKEN (defaults to oauth2)
#:
#: Environment:
#:   HOME             Resolved automatically from /home/homedir.dat
#:   REPOSITORY_TOKEN GitLab personal/project access token exported in the shell for authentication
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/.netrc (created transiently with mode 600 and removed on exit)
#:   - ${HOME}/services/git/gitlab/GitProviderURL.sh
#:   - External binaries: cat, echo, grep, cut, chmod, rm, git
#:
#: Exit Codes:
#:   0          Baseline commit pushed successfully to GitLab
#:   1          Missing required arguments, missing config/helper script, or Git operation failure
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
        /bin/echo "Usage: $0 <repository_owner> <repository_name> [repository_username]" >&2
        exit 1
fi

repository_owner="${1}"
repository_name="${2}"
repository_username="${3}"

# Resolve canonical GitLab host domain via helper script (fallback to gitlab.com)
url_script="${HOME}/services/git/gitlab/GitProviderURL.sh"
if [ -x "${url_script}" ]
then
        provider_url="$("${url_script}")"
else
        provider_url="gitlab.com"
fi

# Guarantee cleanup of transient .netrc credentials and report abnormal exits
netrc_file="${HOME}/.netrc"

handle_exit()
{
        exit_status="$?"
        if [ "${exit_status}" -ne 0 ]
        then
                /bin/echo "Error: Script ($0) aborted unexpectedly with status ${exit_status}." >&2
        fi
        /bin/rm -f "${netrc_file}"
}

trap handle_exit EXIT

# Create scoped .netrc with restricted permissions when REPOSITORY_TOKEN is set
if [ -n "${REPOSITORY_TOKEN}" ]
then
        if [ -z "${repository_username}" ]
        then
                repository_username="oauth2"
        fi

        (
                umask 077
                /bin/cat << EOF > "${netrc_file}"
machine ${provider_url}
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF
        )
        /bin/chmod 600 "${netrc_file}"
fi

# Initialize local Git repository, stage all baseline assets, and push to origin
/usr/bin/git init
/usr/bin/git branch -M main
/usr/bin/git remote add origin "https://${provider_url}/${repository_owner}/${repository_name}.git"

if [ -f .gitattributes ]
then
        /usr/bin/git add .gitattributes
fi

/usr/bin/git add --all -f
/usr/bin/git commit -m "Baseline Baby"
/usr/bin/git push -u origin main

exit 0

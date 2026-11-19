#!/bin/sh
#: Name:        create_repository.sh
#: Purpose:     Redirects repository creation requests to the GitHub API worker.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       create_repository.sh <repository_username> <repository_name>
#:              create_repository.sh [-h|--help]
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
#:   - ${HOME}/services/git/github/api/create_repository.sh
#:   - External binaries: cat, cut, echo, grep
#:
#: Exit Codes:
#:   0          Request delegated and repository created cleanly via API
#:   1          Missing arguments, layout faults, or missing/non-executable API script
#:   *          Bubbled exit code from ${HOME}/services/git/github/api/create_repository.sh
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
        /bin/echo "Error: Repository owner and repository name arguments are required." >&2
        /bin/echo "Usage: $0 <repository_username> <repository_name>" >&2
        exit 1
fi

api_script="${HOME}/services/git/github/api/create_repository.sh"

if [ ! -x "${api_script}" ]
then
        /bin/echo "Error: Target API script not found or not executable at ${api_script}" >&2
        exit 1
fi

exec "${api_script}" "$@"

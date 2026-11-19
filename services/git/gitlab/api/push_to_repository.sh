#!/bin/sh
#: Name:        push_to_repository.sh
#: Purpose:     Redirects repository push requests to the GitLab CLI worker.
#: Author:      Peter Winter
#: Date:        19/11/2026
#: Version:     1.0
#:
#: Usage:       push_to_repository.sh <source_directory> <branch> <repository_username> <repository_ownername> <repository_name>
#:              push_to_repository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Local source directory containing content to push.
#:   $2         [Required] Target branch name or "--branch <name>" flag.
#:   $3         [Required] The GitLab authentication username.
#:   $4         [Required] The GitLab username or group path (repository owner).
#:   $5         [Required] The name/slug of the existing target GitLab project.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/git/gitlab/cli/push_to_repository.sh
#:   - External binaries: cat, cut, echo, grep
#:
#: Exit Codes:
#:   0          Request delegated and directory pushed cleanly via CLI
#:   1          Missing arguments, layout faults, or missing/non-executable CLI script
#:   *          Bubbled exit code from ${HOME}/services/git/gitlab/cli/push_to_repository.sh
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
# along with The Wintersys Agile Deployment Toolkit.  If not, see <http://gnu.org>.
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

if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ] || [ -z "${5}" ]
then
        /bin/echo "Error: Source directory, branch, username, owner name, and project name are required." >&2
        /bin/echo "Usage: $0 <source_directory> <branch> <repository_username> <repository_ownername> <repository_name>" >&2
        exit 1
fi

cli_script="${HOME}/services/git/gitlab/cli/push_to_repository.sh"

if [ ! -x "${cli_script}" ]
then
        /bin/echo "Error: Target CLI script not found or not executable at ${cli_script}" >&2
        exit 1
fi

exec "${cli_script}" "$@"

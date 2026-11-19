#!/bin/sh
#: Name:        CloneRepository.sh
#: Purpose:     Clones or downloads a remote GitLab project branch to a local path.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       CloneRepository.sh <repository_ownername> <repository_name> <repository_branch> <destination_directory>
#:              CloneRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The GitLab username or group path (repository owner).
#:   $2         [Required] The name/slug of the GitLab project to clone.
#:   $3         [Required] The target branch name to clone.
#:   $4         [Required] The local destination directory path.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/runtime/software.dat
#:   - ${HOME}/services/git/gitlab/${orchestration_tool}/clone_repository.sh
#:   - External binaries: awk, cat, cut, echo, grep, ls, tr
#:
#: Exit Codes:
#:   0          Project cloned cleanly and destination directory populated
#:   1          Missing arguments, layout faults, configuration errors, or clone failure
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

# Input validation
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ]
then
        /bin/echo "Error: Missing required arguments." >&2
        /bin/echo "Usage: $0 <repository_ownername> <repository_name> <repository_branch> <destination_directory>" >&2
        exit 1
fi

repository_ownername="${1}"
repository_name="${2}"
repository_branch="${3}"
destination_directory="${4}"

software_file="${HOME}/runtime/software.dat"
if [ ! -f "${software_file}" ] || [ ! -r "${software_file}" ]
then
        /bin/echo "Error: Cannot read software configuration file at ${software_file}" >&2
        exit 1
fi

orchestration_tool="$(/usr/bin/awk -F':' '/^ORCHESTRATION_TOOL:/ {print $NF}' "${software_file}" 2>/dev/null | /bin/tr -d ' ')"

if [ -z "${orchestration_tool}" ]
then
        /bin/echo "Error: ORCHESTRATION_TOOL not found in ${software_file}" >&2
        exit 1
fi

worker_script="${HOME}/services/git/gitlab/${orchestration_tool}/clone_repository.sh"

if [ ! -x "${worker_script}" ]
then
        /bin/echo "Error: Provider clone script not found or not executable at ${worker_script}" >&2
        exit 1
fi

# Temporarily disable set -e to evaluate git transaction failures manually
set +e
output="$(${worker_script} "${repository_branch}" "${repository_ownername}" "${repository_name}" "${destination_directory}")"
clone_status="$?"
set -e

if [ "${clone_status}" -eq 0 ] && [ -d "${destination_directory}" ] && [ -n "$(/bin/ls -A "${destination_directory}")" ]
then
        /bin/echo "${output}"
else
        /bin/echo "failed"
        /bin/echo "Git clone failed for ${repository_ownername}/${repository_name}. Check your API token, branch, or project URL." >&2
        exit 1
fi

exit 0

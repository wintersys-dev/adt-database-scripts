#!/bin/sh
#: Name:        PushToRepository.sh
#: Purpose:     Pushes a local directory with content to a Bitbucket repository.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       PushToRepository.sh <source_directory> <repository_name> [branch] [repository_ownername] [repository_username]
#:              PushToRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Local source directory containing content to push.
#:   $2         [Required] The name/slug of the existing target repository.
#:   $3         [Optional] Target branch name (defaults to "main").
#:   $4         [Optional] The Bitbucket workspace or repository owner name (falls back to APPLICATIONREPOSITORYOWNER).
#:   $5         [Optional] The Bitbucket authentication username (falls back to APPLICATIONREPOSITORYUSERNAME).
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/runtime/software.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/bitbucket/${orchestration_tool}/push_to_repository.sh
#:   - External binaries: awk, cat, cut, echo, grep, tr
#:
#: Exit Codes:
#:   0          Directory pushed cleanly and remote repository URL printed to stdout
#:   1          Missing arguments, invalid directory, layout faults, configuration errors, or push failure
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
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

set +e
source_directory="${1}"
repository_name="${2}"
branch="${3:-main}"
repository_ownername="${4:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYOWNER')}"
repository_username="${5:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYUSERNAME')}"
set -e

# Verify that all required values are set from either arguments or config
if [ -z "${source_directory}" ] || [ -z "${repository_name}" ] || [ -z "${branch}" ] || [ -z "${repository_ownername}" ] || [ -z "${repository_username}" ]
then
        /bin/echo "Error: Source directory, repository name, branch, owner, or username could not be determined." >&2
        /bin/echo "Usage: $0 <source_directory> <repository_name> [branch] [repository_ownername] [repository_username]" >&2
        exit 1
fi

if [ ! -d "${source_directory}" ]
then
        /bin/echo "failed"
        /bin/echo "Error: Source directory not found at ${source_directory}." >&2
        exit 1
fi

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

worker_script="${HOME}/services/git/bitbucket/${orchestration_tool}/push_to_repository.sh"

if [ ! -x "${worker_script}" ]
then
        /bin/echo "Error: Provider push script not found or not executable at ${worker_script}" >&2
        exit 1
fi

# Temporary disable set -e to evaluate git transaction failures manually
set +e
output="$(${worker_script} "${source_directory}" "${branch}" "${repository_username}" "${repository_ownername}" "${repository_name}")"
push_status="$?"
set -e

if [ "${push_status}" -eq 0 ] && [ -n "${output}" ]
then
        /bin/echo "${output}"
else
        /bin/echo "failed"
        /bin/echo "Git push failed for ${repository_ownername}/${repository_name}. Check your API token, branch, or repository permissions." >&2
        exit 1
fi

exit 0

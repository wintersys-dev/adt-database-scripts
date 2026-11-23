#!/bin/sh
#: Name:        ListRepository.sh
#: Purpose:     Checks whether a Gitlab repository is "full", "empty", or "none".
#: Author:      Peter Winter
#: Date:        22/11/2026
#: Version:     1.0
#:
#: Usage:       ListRepository.sh <repository_name> <repository_ownername>
#:              ListRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the repository to inspect.
#:   $2         [Required] The Gitlab workspace or repository owner name.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/runtime/software.dat
#:   - ${HOME}/services/git/gitlab/${orchestration_tool}/list_repository.sh
#:   - External binaries: awk, cat, cut, echo, grep, tr
#:
#: Exit Codes:
#:   0          Repository state ("full", "empty", or "none") printed to stdout
#:   1          Missing arguments, layout faults, configuration errors, or worker failure
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

# Render self-extracting help documentation when -h or --help is supplied
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

if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: Repository name and repository ownername arguments are required." >&2
        /bin/echo "Usage: $0 <repository_name> <repository_ownername>" >&2
        exit 1
fi

repository_name="${1}"
repository_ownername="${2}"

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

worker_script="${HOME}/services/git/gitlab/${orchestration_tool}/list_repository.sh"

if [ ! -x "${worker_script}" ]
then
        /bin/echo "Error: Provider repository check script not found or not executable at ${worker_script}" >&2
        exit 1
fi

# Temporarily disable set -e to evaluate worker execution failures manually
set +e
output="$("${worker_script}" "${repository_name}" "${repository_ownername}")"
worker_status="$?"
set -e

if [ "${worker_status}" -eq 0 ] && [ -n "${output}" ]
then
        case "${output}" in
                full|empty|none)
                        /bin/echo "${output}"
                        exit 0
                        ;;
                *)
                        /bin/echo "none"
                        /bin/echo "Error: Unexpected repository state returned: ${output}" >&2
                        exit 1
                        ;;
        esac
else
        /bin/echo "none"
        /bin/echo "Repository check failed for ${repository_ownername}/${repository_name}. Check your API token or configuration." >&2
        exit 1
fi

exit 0


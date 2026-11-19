#!/bin/sh
#: Name:        CreateRepository.sh
#: Purpose:     Creates a new private Bitbucket Git repository and outputs its HTTPS clone URL.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       CreateRepository.sh <repository_username> <repository_name>
#:
#: Parameters:
#:   $1         [Required] The Bitbucket workspace or repository username.
#:   $2         [Required] The name/slug of the repository to create.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/runtime/software.dat
#:   - ${HOME}/services/git/bitbucket/${orchestration_tool}/create_repository.sh
#:   - External binaries: awk, cat, echo, jq, tr
#:
#: Exit Codes:
#:   0          Repository created cleanly and HTTPS clone URL printed to stdout
#:   1          Missing arguments, layout faults, configuration errors, worker failure, or clone URL parse error
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

if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

# Input validation
if [ -z "${1}" ] || [ -z "${2}" ]
then
        /bin/echo "Error: Repository username and repository name arguments are required." >&2
        /bin/echo "Usage: $0 <repository_username> <repository_name>" >&2
        exit 1
fi

repository_username="${1}"
repository_name="${2}"

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

# Temporary disable set -e to evaluate curl transaction pipeline failures manually
set +e
response="$(${HOME}/services/git/bitbucket/${orchestration_tool}/create_repository.sh "${repository_username}" "${repository_name}")"
curl_status="$?"
set -e

if [ "${curl_status}" -eq 0 ] && [ -n "${response}" ]
then
        output="$(/bin/echo "${response}" | /usr/bin/jq -r '.links.clone[] | select(.name == "https").href')"

        if [ -z "${output}" ]
        then
                /bin/echo "Error: Repository created, but no HTTPS clone URL found for ${repository_username}/${repository_name}." >&2
                exit 1
        else
                /bin/echo "${output}"
        fi
else
        /bin/echo "Network request failed. Check your API token, email, or repository name." >&2
        exit 1
fi

exit 0


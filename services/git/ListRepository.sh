#!/bin/sh
#: Name:        ListRepository.sh
#: Purpose:     Orchestrates remote repository status checks across configured Git providers.
#: Author:      Peter Winter
#: Date:        22/11/2026
#: Version:     1.0
#:
#: Usage:       ListRepository.sh <repository_name> [repository_provider] [repository_ownername]
#:              ListRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the repository to inspect.
#:   $2         [Optional] The Git provider name (e.g. bitbucket, github, gitlab).
#:   $3         [Optional] The workspace or repository owner name.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/${repository_provider}/ListRepository.sh
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Repository check delegated and completed cleanly by provider sub-driver
#:   1          Missing arguments, layout faults, missing/non-executable sub-driver, or check failure
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
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

# Validate minimum required positional arguments
if [ -z "${1}" ]
then
        /bin/echo "Error: <repository_name> argument is required" >&2
        /bin/echo "Usage: $0 <repository_name> [repository_provider] [repository_ownername]" >&2
        exit 1
fi

repository_name="${1}"
repository_provider="${2:-$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYPROVIDER')}"
repository_ownername="${3:-$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYOWNER')}"

# Ensure optional parameters resolved cleanly either via CLI or environment fallback
if [ -z "${repository_provider}" ] || [ -z "${repository_ownername}" ]
then
        /bin/echo "Error: Could not resolve repository_provider or repository_ownername from arguments or toolkit configuration" >&2
        exit 1
fi

# Verify provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/git/${repository_provider}/ListRepository.sh"

if [ ! -f "${provider_script}" ]
then
        /bin/echo "Error: Git provider script not found at ${provider_script}" >&2
        exit 1
fi

if [ ! -x "${provider_script}" ]
then
        /bin/echo "Error: Git provider script at ${provider_script} is not executable." >&2
        exit 1
fi

# Delegate remote repository check to the provider-specific sub-driver
set +e
"${provider_script}" "${repository_name}" "${repository_ownername}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} returned error code ${exit_code}." >&2
        exit 1
fi

exit 0

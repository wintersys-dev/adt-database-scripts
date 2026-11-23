#!/bin/sh
#: Name:        CreateRepository.sh
#: Purpose:     Orchestrates private repository creation across configured Git providers.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       CreateRepository.sh <repository_name> [repository_provider] [repository_username] 
#:              CreateRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the repository to create.
#:   $2         [Optional] The Git provider name (falls back to APPLICATIONREPOSITORYPROVIDER).
#:   $3         [Optional] The workspace or repository username (falls back to APPLICATIONREPOSITORYUSERNAME).
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/${repository_provider}/CreateRepository.sh
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Repository creation delegated and completed cleanly by provider sub-driver
#:   1          Missing arguments, layout faults, missing/non-executable sub-driver, or creation failure
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

set +e
repository_name="${1}"
repository_provider="${2:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYPROVIDER')}"
repository_username="${3:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYUSERNAME')}"
set -e

# Verify that all required values are set from either arguments or config
if [ -z "${repository_name}" ] || [ -z "${repository_provider}" ] || [ -z "${repository_username}" ]
then
        /bin/echo "Error: Repository name, repository provider, or repository username could not be determined from arguments or config." >&2
        /bin/echo "Usage: $0 <repository_name> [repository_provider] [repository_username]" >&2
        exit 1
fi

# Verify provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/git/${repository_provider}/CreateRepository.sh"

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

# Delegate repository creation to the provider-specific sub-driver
set +e
"${provider_script}" "${repository_username}" "${repository_name}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} exited with error code ${exit_code}." >&2
        exit 1
fi

exit 0


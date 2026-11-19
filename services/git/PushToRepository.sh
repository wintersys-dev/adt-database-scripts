#!/bin/sh
#: Name:        PushToRepository.sh
#: Purpose:     Orchestrates repository push operations across configured Git providers.
#: Author:      Peter Winter
#: Date:        18/11/2026
#: Version:     1.0
#:
#: Usage:       PushToRepository.sh <source_directory> <repository_name> [repository_branch] [repository_provider] [repository_owner] [repository_username]
#:              PushToRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Local source directory containing content to push.
#:   $2         [Required] The name/slug of the target repository.
#:   $3         [Optional] Target branch name (defaults to "main").
#:   $4         [Optional] The Git provider name (falls back to APPLICATIONREPOSITORYPROVIDER).
#:   $5         [Optional] The workspace or repository owner name (falls back to APPLICATIONREPOSITORYOWNER).
#:   $6         [Optional] The repository authentication username (falls back to APPLICATIONREPOSITORYUSERNAME).
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/${repository_provider}/PushToRepository.sh
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Repository push delegated and completed cleanly by provider sub-driver
#:   1          Missing arguments, invalid directory, layout faults, missing/non-executable sub-driver, or push failure
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

set +e
source_directory="${1}"
repository_name="${2}"
repository_branch="${3:-main}"
repository_provider="${4:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYPROVIDER')}"
repository_owner="${5:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYOWNER')}"
repository_username="${6:-$(${HOME}/utilities/config/ExtractConfigValue.sh 'APPLICATIONREPOSITORYUSERNAME')}"
set -e

# Verify that all required values are set from either arguments or config
if [ -z "${source_directory}" ] || [ -z "${repository_name}" ] || [ -z "${repository_branch}" ] || [ -z "${repository_provider}" ] || [ -z "${repository_owner}" ] || [ -z "${repository_username}" ]
then
        /bin/echo "Error: Source directory, repository name, branch, provider, owner, or username could not be determined from arguments or config." >&2
        /bin/echo "Usage: $0 <source_directory> <repository_name> [repository_branch] [repository_provider] [repository_owner] [repository_username]" >&2
        exit 1
fi

if [ ! -d "${source_directory}" ]
then
        /bin/echo "Error: Source directory not found at ${source_directory}." >&2
        exit 1
fi

# Verify provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/git/${repository_provider}/PushToRepository.sh"

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

# Delegate push operation to the provider-specific sub-driver
set +e
"${provider_script}" "${source_directory}" "${repository_name}" "${repository_branch}" "${repository_owner}" "${repository_username}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} exited with error code ${exit_code}." >&2
        exit 1
fi

exit 0


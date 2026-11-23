#!/bin/sh
#: Name:        CloneRepository.sh
#: Purpose:     Orchestrates repository cloning across configured Git providers on a webserver machine.
#: Author:      Peter Winter
#: Date:        22/11/2026
#: Version:     1.0
#:
#: Usage:       CloneRepository.sh <repository_name> <repository_branch> <destination_directory> [repository_provider] [repository_ownername]
#:              CloneRepository.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The name/slug of the repository to clone.
#:   $2         [Required] The target branch name to clone.
#:   $3         [Required] The local destination directory path.
#:   $4         [Optional] The Git provider name (e.g. bitbucket, github, gitlab).
#:   $5         [Optional] The workspace or repository owner name.
#:
#: Environment:
#:   HOME       Root directory of the ADT webserver scripts (e.g. /root)
#:
#: Dependencies:
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/${repository_provider}/CloneRepository.sh
#:   - External binaries: echo, grep, cut
#:
#: Exit Codes:
#:   0          Repository cloned cleanly by provider sub-driver
#:   1          Missing arguments, layout faults, missing/non-executable sub-driver, or clone failure
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

# Verify HOME is set and points to the ADT webserver directory
if [ -z "${HOME}" ] 
then
        /bin/echo "Webserver toolkit root directory not found at ${HOME}" >&2
        exit 1
fi

# Validate minimum required positional arguments
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
then
        /bin/echo "Error: 3 arguments are required with 2 optional arguments." >&2
        /bin/echo "Usage: $0 <repository_name> <repository_branch> <destination_directory> [repository_provider] [repository_ownername]" >&2
        exit 1
fi

repository_name="${1}"
repository_branch="${2}"
destination_directory="${3}"

# Extract defaults from webserver configuration if optional parameters are omitted
if [ -n "${4}" ]
then
        repository_provider="${4}"
else
        repository_provider="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYPROVIDER')"
fi

if [ -n "${5}" ]
then
        repository_ownername="${5}"
else
        repository_ownername="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'APPLICATIONREPOSITORYOWNER')"
fi

# Verify provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/git/${repository_provider}/CloneRepository.sh"

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

# Delegate clone operation to the provider-specific sub-driver
set +e
"${provider_script}" "${repository_name}" "${repository_branch}" "${destination_directory}" "${repository_ownername}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} exited with error code ${exit_code}." >&2
        exit 1
fi

exit 0

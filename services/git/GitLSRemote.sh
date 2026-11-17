#!/bin/sh
#: Name:        GitLSRemote.sh
#: Purpose:     Checks whether a remote repository exists by delegating to the configured Git provider sub-driver.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       GitLSRemote.sh "<repository_provider>" "<repository_ownername>" "<repository_name>" ["<repository_username>"]
#:              GitLSRemote.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Hosting vendor identifier (e.g. github, gitlab, bitbucket)
#:   $2         [Required] Organisation or user namespace account name
#:   $3         [Required] Case-sensitive target repository name
#:   $4         [Optional] Account username or credential identifier for authenticated lookups
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/git/<repository_provider>/GitLSRemote.sh
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Remote repository verified via provider sub-driver
#:   1          Missing required arguments, missing config/provider script, or remote lookup failure
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
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
then
        /bin/echo "Error: 3 arguments are required and 1 optional argument." >&2
        /bin/echo "Usage: $0 <repository_provider> <repository_ownername> <repository_name> [repository_username]" >&2
        exit 1
fi

repository_provider="${1}"
repository_ownername="${2}"
repository_name="${3}"
repository_username="${4}"

# Verify provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/git/${repository_provider}/GitLSRemote.sh"

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
"${provider_script}" "${repository_ownername}" "${repository_name}" "${repository_username}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} returned error code ${exit_code}." >&2
        exit 1
fi

exit 0

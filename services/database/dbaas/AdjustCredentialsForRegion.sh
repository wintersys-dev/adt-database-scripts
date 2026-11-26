#!/bin/sh
#: Name:        AdjustCredentialsForRegion.sh
#: Purpose:     Strips provider/role prefixes delimited by ":::" from stored DBUSERNAME and DBPASSWORD config values.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       NormaliseDBCredentials.sh
#:              NormaliseDBCredentials.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads DBUSERNAME and DBPASSWORD from configuration, strips any "<prefix>:::" qualifier, and persists updates.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/StoreConfigValue.sh
#:   - External binaries: cat, echo, grep, cut
#:
#: Exit Codes:
#:   0          Database credentials inspected and persisted cleanly
#:   1          Missing /home/homedir.dat, missing config helpers, or credential read/write failure
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

# Resolve the server toolkit root directory from /home/homedir.dat
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
        export HOME
else
        /bin/echo "Application framework configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: Resolved HOME directory '${HOME}' is invalid." >&2
        exit 1
fi

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
config_storer="${HOME}/utilities/config/StoreConfigValue.sh"

if [ ! -x "${config_extractor}" ] || [ ! -x "${config_storer}" ]
then
        /bin/echo "Error: Configuration helper scripts missing or not executable under ${HOME}/utilities/config/" >&2
        exit 1
fi

set +e
DB_U="$("${config_extractor}" 'DBUSERNAME')"
DB_P="$("${config_extractor}" 'DBPASSWORD')"
set -e

case "${DB_U}" in
        *::*)
                DB_U="${DB_U#*:::}"
                ;;
esac

case "${DB_P}" in
        *::*)
                DB_P="${DB_P#*:::}"
                ;;
esac

if [ -n "${DB_U}" ]
then
        "${config_storer}" 'DBUSERNAME' "${DB_U}"
fi

if [ -n "${DB_P}" ]
then
        "${config_storer}" 'DBPASSWORD' "${DB_P}"
fi

exit 0
 

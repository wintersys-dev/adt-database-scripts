#!/bin/sh
#: Name:        KnickersUp.sh
#: Purpose:     Routes restrictive firewall lockdown activation (KnickersUp) to the active firewall backend.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       KnickersUp.sh
#:              KnickersUp.sh [-h|--help]
#:
#: Parameters:
#:   None       Resolves FIREWALL build style value and invokes the corresponding backend KnickersUp.sh.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/services/security/firewall/<firewall_type>/KnickersUp.sh
#:   - External binaries: cat, echo, grep, cut, awk
#:
#: Exit Codes:
#:   0          Firewall lockdown verified with no rule modifications needed
#:   1          Missing /home/homedir.dat, missing FIREWALL style, or missing/failed backend driver
#:   10         Firewall lockdown rules applied/updated (signals ReloadFirewall.sh)
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

style_extractor="${HOME}/utilities/config/ExtractBuildStyleValues.sh"
if [ ! -x "${style_extractor}" ]
then
        /bin/echo "Error: ExtractBuildStyleValues.sh missing or not executable at ${style_extractor}" >&2
        exit 1
fi

set +e
firewall_type="$("${style_extractor}" "FIREWALL" | /usr/bin/awk -F':' '{print $2}')"
set -e

if [ -z "${firewall_type}" ]
then
        /bin/echo "Error: Failed to resolve active FIREWALL type from build style configuration." >&2
        exit 1
fi

lockdown_script="${HOME}/services/security/firewall/${firewall_type}/KnickersUp.sh"
if [ ! -x "${lockdown_script}" ]
then
        /bin/echo "Error: Firewall lockdown driver missing or not executable at ${lockdown_script}" >&2
        exit 1
fi

exec "${lockdown_script}"



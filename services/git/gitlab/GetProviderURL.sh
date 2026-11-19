#!/bin/sh
#: Name:        GetProviderURL.sh
#: Purpose:     Outputs the base domain identifier string for the GitLab hosting platform.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       GetProviderURL.sh
#:              GetProviderURL.sh [-h|--help]
#:
#: Parameters:
#:   None
#:
#: Environment:
#:   None
#:
#: Dependencies:
#:   - External binaries: echo, grep, cut
#:
#: Exit Codes:
#:   0          Base provider domain emitted successfully on stdout
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

# Emit the canonical domain identifier for GitLab
/bin/echo "gitlab.com"

exit 0

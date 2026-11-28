#!/bin/sh
#: Name:        SendEmail.sh
#: Purpose:     Orchestrates sending emails across configured email utilities on a webserver machine.
#: Author:      Peter Winter
#: Date:        28/11/2026
#: Version:     1.0
#:
#: Usage:       SendEmail.sh <subject> <message> <level> [to_address] [content_type]
#:              SendEmail.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The subject line of the email.
#:   $2         [Required] The body text of the email.
#:   $3         [Required] The notification severity level (e.g. ERROR, INFO, MANDATORY).
#:   $4         [Optional] The recipient email address or alias (defaults to "system").
#:   $5         [Optional] The email content type (defaults to "default").
#:
#: Environment:
#:   HOME       Root directory of the ADT webserver scripts (e.g. /root)
#:
#: Dependencies:
#:   - ${HOME}/utilities/processing/GetPublicIP.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/services/email/${email_util}/SendEmail.sh
#:   - External binaries: echo, grep, cut, cat, awk
#:
#: Exit Codes:
#:   0          Email sent cleanly by provider sub-driver or skipped due to notification level rules
#:   1          Missing arguments, layout faults, missing/non-executable sub-driver, or send failure
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
        /bin/echo "Error: Minimum of 3 arguments required with 2 optional arguments." >&2
        /bin/echo "Usage: $0 <subject> <message> <level> [to_address] [content_type]" >&2
        exit 1
fi

subject="${1}"
message="${2}"
level="${3}"

# Set defaults for optional parameters if omitted
if [ -n "${4}" ]
then
        to_address="${4}"
else
        to_address="system"
fi

if [ -n "${5}" ]
then
        content_type="${5}"
else
        content_type="default"
fi

# Skip non-mandatory, non-error notifications if notification level is restricted to ERROR
if [ "${level}" != "MANDATORY" ] && [ "${level}" != "ERROR" ]
then
        if [ "$("${HOME}/utilities/config/CheckConfigValue.sh" "EMAILNOTIFICATIONLEVEL:ERROR")" = "1" ]
        then
                exit 0
        fi
fi

# Prepend machine public IP address for standard alert levels
if [ "${level}" = "ERROR" ] || [ "${level}" = "INFO" ] || [ "${level}" = "MANDATORY" ]
then
        ip_address="$("${HOME}/utilities/processing/GetPublicIP.sh")"
        message="MESSAGE RELATED TO MACHINE WITH IP ADDRESS: ${ip_address}: ${message}"
fi

# Resolve configured email utility sub-driver
email_util="$("${HOME}/utilities/config/ExtractBuildStyleValues.sh" "EMAILUTIL" | /usr/bin/awk -F':' '{print $NF}')"

if [ -z "${email_util}" ]
then
        /bin/echo "Error: Unable to determine configured EMAILUTIL value." >&2
        exit 1
fi

# Verify email provider sub-driver script exists and is executable before delegating
provider_script="${HOME}/services/email/${email_util}/SendEmail.sh"

if [ ! -f "${provider_script}" ]
then
        /bin/echo "Error: Email provider script not found at ${provider_script}" >&2
        exit 1
fi

if [ ! -x "${provider_script}" ]
then
        /bin/echo "Error: Email provider script at ${provider_script} is not executable." >&2
        exit 1
fi

# Delegate email dispatch to the provider-specific sub-driver
set +e
"${provider_script}" "${subject}" "${message}" "${to_address}" "${content_type}"
exit_code="$?"
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: ${provider_script} exited with error code ${exit_code}." >&2
        exit 1
fi

exit 0

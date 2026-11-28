#!/bin/sh
#: Name:        SendEmail.sh (sendemail)
#: Purpose:     Sends emails via the sendemail CLI utility using configured SMTP provider settings.
#: Author:      Peter Winter
#: Date:        28/11/2026
#: Version:     1.0
#:
#: Usage:       SendEmail.sh <subject> <message> <to_address> [content_type]
#:              SendEmail.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] The subject line of the email.
#:   $2         [Required] The body text of the email.
#:   $3         [Required] The recipient email address or "system" for the configured system recipient.
#:   $4         [Optional] The email content type (accepted for dispatcher interface compatibility; e.g. "HTML", "default").
#:
#: Environment:
#:   HOME       Root directory of the ADT webserver scripts (e.g. /root)
#:
#: Dependencies:
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: echo, grep, cut, cat, date, sendemail
#:
#: Exit Codes:
#:   0          Email dispatched cleanly via sendemail
#:   1          Missing arguments, layout faults, invalid provider config, or send failure
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
        /bin/echo "Error: Minimum of 3 arguments required with 1 optional argument." >&2
        /bin/echo "Usage: $0 <subject> <message> <to_address> [content_type]" >&2
        exit 1
fi

subject="${1}"
message="${2}"
to_address="${3}"
content_type="${4}"

# Extract SMTP and sender configuration values
email_provider="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'EMAILPROVIDER')"
from_address="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'SYSTEMFROMEMAILADDRESS')"
username="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'EMAILUSERNAME')"
password="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'EMAILPASSWORD')"

# Resolve recipient address ("system" maps to configured SYSTEMTOEMAILADDRESS)
if [ "${to_address}" = "system" ]
then
        target_address="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'SYSTEMTOEMAILADDRESS')"
else
        target_address="${to_address}"
fi

if [ -z "${target_address}" ]
then
        /bin/echo "Error: Target recipient email address could not be resolved." >&2
        exit 1
fi

# Resolve SMTP server host and port from configured provider ID
case "${email_provider}" in
        1)
                smtp_server="smtp-pulse.com:2525"
                ;;
        2)
                smtp_server="in-v3.mailjet.com:587"
                ;;
        3)
                smtp_server="email-smtp.eu-west-1.amazonaws.com:587"
                ;;
        *)
                /bin/echo "Error: Unsupported or unconfigured EMAILPROVIDER value '${email_provider}'." >&2
                exit 1
                ;;
esac

# Verify sendemail binary is available and executable
if [ ! -x /usr/bin/sendemail ]
then
        /bin/echo "Error: sendemail binary not found or not executable at /usr/bin/sendemail" >&2
        exit 1
fi

# Dispatch email via sendemail and capture exit status explicitly
current_date="$(/bin/date)"

set +e
if [ "${content_type}" = "HTML" ]
then
        /usr/bin/sendemail -o tls=no -o message-content-type=html -f "${from_address}" -t "${target_address}" -s "${smtp_server}" -xu "${username}" -xp "${password}" -u "${subject} ${current_date}" -m "${message}"
        exit_code="$?"
else
        /usr/bin/sendemail -o tls=no -f "${from_address}" -t "${target_address}" -s "${smtp_server}" -xu "${username}" -xp "${password}" -u "${subject} ${current_date}" -m "${message}"
        exit_code="$?"
fi
set -e

if [ "${exit_code}" -ne 0 ]
then
        /bin/echo "Error: Failed to send email via sendemail (exit code ${exit_code})." >&2
        exit 1
fi

exit 0

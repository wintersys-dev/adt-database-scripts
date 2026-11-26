#!/bin/sh
#: Name:        DenyAuthenticator.sh
#: Purpose:     Adds idempotent UFW DENY rules isolating non-auth hosts from authenticator IP addresses.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       DenyAuthenticator.sh
#:              DenyAuthenticator.sh [-h|--help]
#:
#: Parameters:
#:   None       Fetches authenticatorip/* and authenticatorpublicip/* from the config datastore on non-auth hosts.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut, hostname
#:
#: Exit Codes:
#:   0          UFW isolation rules verified or host is an authenticator; no changes made
#:   1          Missing /home/homedir.dat, missing required tools, or UFW execution failure
#:   10         Active UFW ruleset updated with authenticator DENY rules (signals ReloadFirewall.sh)
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

host_name="$(/usr/bin/hostname)"
case "${host_name}" in
        *-auth-*)
                exit 0
                ;;
esac

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

list_wrapper="${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh"
if [ ! -x "${list_wrapper}" ]
then
        /bin/echo "Error: ListFromDatastore.sh missing or not executable at ${list_wrapper}" >&2
        exit 1
fi

set +e
authenticator_ips="$("${list_wrapper}" "config" "authenticatorip/*" 2>/dev/null)"
authenticator_public_ips="$("${list_wrapper}" "config" "authenticatorpublicip/*" 2>/dev/null)"
ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
set -e

updated="0"

add_deny_rule()
{
        raw_ip="${1}"
        [ -z "${raw_ip}" ] && return 0

        if ! printf '%s\n' "${raw_ip}" | /usr/bin/grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
        then
                /bin/echo "Warning: Skipping invalid authenticator IP entry '${raw_ip}'." >&2
                return 0
        fi

        if ! printf '%s\n' "${ufw_status}" | /bin/grep -Eq "^Anywhere[[:space:]]+DENY[[:space:]]+${raw_ip}([[:space:]]|$)"
        then
                /usr/sbin/ufw deny from "${raw_ip}" >/dev/null
                updated="1"
                set +e
                ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
                set -e
        fi
}

for ip in ${authenticator_ips} ${authenticator_public_ips}
do
        add_deny_rule "${ip}"
done

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


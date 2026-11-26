#!/bin/sh
#: Name:        MonitorFirewall.sh
#: Purpose:     Audits live UFW firewall status and sends email alerts if UFW becomes inactive.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       MonitorFirewall.sh
#:              MonitorFirewall.sh [-h|--help]
#:
#: Parameters:
#:   None       Checks ACTIVEFIREWALLS, host uptime (>= 600s), INSTALLED_SUCCESSFULLY, and ufw status.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh
#:   - ${HOME}/utilities/processing/GetPublicIP.sh
#:   - ${HOME}/services/email/SendEmail.sh
#:   - /usr/sbin/ufw
#:   - External binaries: cat, echo, printf, grep, cut, awk, rm
#:
#: Exit Codes:
#:   0          Firewall status audited cleanly (healthy, bypassed, or alert dispatched)
#:   1          Missing /home/homedir.dat or missing /usr/sbin/ufw binary
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

config_checker="${HOME}/utilities/config/CheckConfigValue.sh"
if [ "$("${config_checker}" 'ACTIVEFIREWALLS:1')" = "0" ] && [ "$("${config_checker}" 'ACTIVEFIREWALLS:3')" = "0" ]
then
        exit 0
fi

uptime_secs="$(/usr/bin/awk -F'.' '{print $1}' /proc/uptime)"
if [ "${uptime_secs:-0}" -lt 600 ]
then
        exit 0
fi

set +e
installed_flag="$("${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh" "config" "INSTALLED_SUCCESSFULLY" 2>/dev/null)"
set -e

if [ -z "${installed_flag}" ]
then
        exit 0
fi

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

set +e
ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
set -e

if ! printf '%s\n' "${ufw_status}" | /bin/grep -q '^Status: active'
then
        set +e
        public_ip="$("${HOME}/utilities/processing/GetPublicIP.sh" 2>/dev/null)"
        "${HOME}/services/email/SendEmail.sh" \
                "FIREWALL (ufw) INACTIVE" \
                "Just so you know, your firewall is inactive on machine ${public_ip:-unknown}. The machine may still be initialising after a reboot, which can take some minutes, but if these messages continue indefinitely, then you need to look into why the firewall is inactive." \
                "ERROR"
        set -e

        if [ -f "${HOME}/runtime/FIREWALL-ACTIVE" ]
        then
                /bin/rm -f "${HOME}/runtime/FIREWALL-ACTIVE"
        fi
fi

exit 0



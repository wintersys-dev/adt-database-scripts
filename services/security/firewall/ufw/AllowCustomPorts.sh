#!/bin/sh
#: Name:        AllowCustomPorts.sh
#: Purpose:     Synchronizes custom UFW allow/limit rules and Cloudflare edge CIDR entries from firewall.dat.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       AllowCustomPorts.sh
#:              AllowCustomPorts.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads NOREVERSEPROXIES, FIREWALL mode, and ${HOME}/runtime/firewall.dat.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/runtime/firewall.dat
#:   - /usr/sbin/ufw
#:   - /usr/bin/curl
#:   - External binaries: cat, echo, printf, grep, cut, awk, sed, hostname
#:
#: Exit Codes:
#:   0          Custom UFW port rules verified; no structural changes applied
#:   1          Missing /home/homedir.dat, missing required tools, or UFW execution failure
#:   10         Active UFW ruleset updated with custom port changes (signals ReloadFirewall.sh)
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

if [ ! -x /usr/sbin/ufw ]
then
        /bin/echo "Error: /usr/sbin/ufw not found or not executable." >&2
        exit 1
fi

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
style_extractor="${HOME}/utilities/config/ExtractBuildStyleValues.sh"

set +e
NO_REVERSE_PROXIES="$("${config_extractor}" 'NOREVERSEPROXIES')"
fw_mode="$("${style_extractor}" "FIREWALL" | /usr/bin/awk -F':' '{print $3}')"
set -e

if [ "${fw_mode}" = "limit" ]
then
        openness="limit"
else
        openness="allow"
fi

host_name="$(/usr/bin/hostname)"
case "${host_name}" in
        ws-*)
                if [ "${NO_REVERSE_PROXIES}" != "0" ]
                then
                        openness="allow"
                fi
                ;;
esac

# Check whether a UFW rule for (port, ip_address) already exists in `ufw status`
ufw_rule_exists()
{
        check_port="${1}"
        check_ip="${2}"
        status_snapshot="${3}"

        if [ "${check_ip}" = "0.0.0.0/0" ]
        then
                src_pattern="Anywhere"
        else
                src_pattern="${check_ip}"
        fi

        printf '%s\n' "${status_snapshot}" | /bin/grep -Eq "^${check_port}(/tcp)?[[:space:]]+(ALLOW|LIMIT)[[:space:]]+${src_pattern}([[:space:]]|$)"
}

updated="0"
firewall_dat="${HOME}/runtime/firewall.dat"

if [ -f "${firewall_dat}" ]
then
        ports=""
        case "${host_name}" in
                *-rp-*)
                        ports="$(/bin/grep "^REVERSEPROXYPORTS:" "${firewall_dat}" 2>/dev/null | /bin/sed 's/^REVERSEPROXYPORTS://g' || true)"
                        ;;
                ws-*)
                        ports="$(/bin/grep "^WEBSERVERPORTS:" "${firewall_dat}" 2>/dev/null | /bin/sed 's/^WEBSERVERPORTS://g' || true)"
                        ;;
                *-auth-*)
                        ports="$(/bin/grep "^AUTHENTICATORPORTS:" "${firewall_dat}" 2>/dev/null | /bin/sed 's/^AUTHENTICATORPORTS://g' || true)"
                        ;;
        esac

        set +e
        ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
        set -e

        for port_token in ${ports}
        do
                delete="no"
                port=""
                ip_address=""

                case "${port_token}" in
                        *ipv4*)
                                port="$(printf '%s\n' "${port_token}" | /usr/bin/awk -F'|' '{print $1}')"
                                ip_address="$(printf '%s\n' "${port_token}" | /usr/bin/awk -F'|' '{print $4}')"
                                if [ "$(printf '%s\n' "${port_token}" | /usr/bin/awk -F'|' '{print $6}')" = "DELETE" ]
                                then
                                        delete="yes"
                                fi
                                ;;
                        *)
                                continue
                                ;;
                esac

                if [ -z "${port}" ] || [ -z "${ip_address}" ]
                then
                        continue
                fi

                if [ "${ip_address}" = "cloudflare" ]
                then
                        cf_ips="$(/usr/bin/curl -fsSL --connect-timeout 10 --max-time 30 "https://cloudflare.com" 2>/dev/null || true)"
                        for ip in ${cf_ips}
                        do
                                printf '%s\n' "${ip}" | /usr/bin/grep -Eq '^[0-9.]+/[0-9]+$' || continue

                                if [ "${delete}" = "yes" ]
                                then
                                        if ufw_rule_exists "${port}" "${ip}" "${ufw_status}"
                                        then
                                                /usr/sbin/ufw delete allow from "${ip}" to any port "${port}" >/dev/null 2>&1 || true
                                                /usr/sbin/ufw delete limit from "${ip}" to any port "${port}" >/dev/null 2>&1 || true
                                                updated="1"
                                        fi
                                elif ! ufw_rule_exists "${port}" "${ip}" "${ufw_status}"
                                then
                                        /usr/sbin/ufw "${openness}" from "${ip}" to any port "${port}" >/dev/null
                                        updated="1"
                                fi
                        done
                        set +e
                        ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
                        set -e
                elif [ "${delete}" != "yes" ]
                then
                        if ! ufw_rule_exists "${port}" "${ip_address}" "${ufw_status}"
                        then
                                /usr/sbin/ufw "${openness}" from "${ip_address}" to any port "${port}" >/dev/null
                                updated="1"
                                set +e
                                ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
                                set -e
                        fi
                else
                        if ufw_rule_exists "${port}" "${ip_address}" "${ufw_status}"
                        then
                                /usr/sbin/ufw delete allow from "${ip_address}" to any port "${port}" >/dev/null 2>&1 || true
                                /usr/sbin/ufw delete limit from "${ip_address}" to any port "${port}" >/dev/null 2>&1 || true
                                updated="1"
                                set +e
                                ufw_status="$(/usr/sbin/ufw status 2>/dev/null)"
                                set -e
                        fi
                fi
        done
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


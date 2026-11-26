#!/bin/sh
#: Name:        AllowCustomPorts.sh
#: Purpose:     Synchronizes custom ingress/egress port rules and Cloudflare edge CIDR allowances in iptables.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       AllowCustomPorts.sh
#:              AllowCustomPorts.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads NOREVERSEPROXIES, FIREWALL rate limits, and ${HOME}/runtime/firewall.dat.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/runtime/firewall.dat
#:   - /usr/sbin/iptables
#:   - /usr/bin/curl
#:   - External binaries: cat, echo, printf, grep, cut, awk, sed, hostname
#:
#: Exit Codes:
#:   0          Custom port rules verified; no netfilter modifications applied
#:   1          Missing /home/homedir.dat, missing required tools, or rule enforcement failure
#:   10         Active iptables chains updated with custom port rules (signals ReloadFirewall.sh)
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

if [ ! -x /usr/sbin/iptables ]
then
        /bin/echo "Error: /usr/sbin/iptables not found or not executable." >&2
        exit 1
fi

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
style_extractor="${HOME}/utilities/config/ExtractBuildStyleValues.sh"

set +e
NO_REVERSE_PROXIES="$("${config_extractor}" 'NOREVERSEPROXIES')"
firewall_style="$("${style_extractor}" "FIREWALL")"
set -e

limit="$(printf '%s\n' "${firewall_style}" | /usr/bin/awk -F':' '{print $3}')"
limit_burst="$(printf '%s\n' "${firewall_style}" | /usr/bin/awk -F':' '{print $4}')"

limited="off"
if [ -n "${limit}" ] && [ -n "${limit_burst}" ]
then
        if [ "${limit}" -eq "${limit}" ] 2>/dev/null && [ "${limit_burst}" -eq "${limit_burst}" ] 2>/dev/null
        then
                limited="on"
        fi
fi

host_name="$(/usr/bin/hostname)"
case "${host_name}" in
        ws-*)
                if [ "${NO_REVERSE_PROXIES}" != "0" ]
                then
                        limited="off"
                fi
                ;;
esac

updated="0"

ensure_rule_append()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -A "$@"
                updated="1"
        fi
}

ensure_rule_insert()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -I "$@"
                updated="1"
        fi
}

delete_rule_if_present()
{
        while /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        do
                /usr/sbin/iptables -D "$@"
                updated="1"
        done
}
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
                                        delete_rule_if_present INPUT -s "${ip}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 30 -j ACCEPT
                                        delete_rule_if_present INPUT -s "${ip}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -j DROP
                                        delete_rule_if_present INPUT -s "${ip}" -p tcp --dport "${port}" -j ACCEPT
                                        delete_rule_if_present OUTPUT -d "${ip}" -p tcp --sport "${port}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                                elif [ "${limited}" = "on" ]
                                then
                                        ensure_rule_append INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                                        ensure_rule_append INPUT -s "${ip}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 30 -j ACCEPT
                                        ensure_rule_append INPUT -s "${ip}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -j DROP
                                        ensure_rule_append OUTPUT -d "${ip}" -p tcp --sport "${port}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                                else
                                        ensure_rule_insert INPUT -s "${ip}" -p tcp --dport "${port}" -j ACCEPT
                                fi
                        done
                elif [ "${delete}" != "yes" ]
                then
                        if [ "${limited}" = "on" ]
                        then
                                ensure_rule_append INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                                ensure_rule_append INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -m limit --limit "${limit}/min" --limit-burst "${limit_burst}" -j ACCEPT
                                ensure_rule_append INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -j DROP
                                ensure_rule_append OUTPUT -d "${ip_address}" -p tcp --sport "${port}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                        else
                                ensure_rule_append INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                                ensure_rule_append OUTPUT -d "${ip_address}" -p tcp --sport "${port}" -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        fi
                else
                        delete_rule_if_present INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -m limit --limit "${limit}/min" --limit-burst "${limit_burst}" -j ACCEPT
                        delete_rule_if_present INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW -j DROP
                        delete_rule_if_present INPUT -s "${ip_address}" -p tcp --dport "${port}" -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                        delete_rule_if_present INPUT -s "${ip_address}" -p tcp --dport "${port}" -j ACCEPT
                        delete_rule_if_present OUTPUT -d "${ip_address}" -p tcp --sport "${port}" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                        delete_rule_if_present OUTPUT -d "${ip_address}" -p tcp --sport "${port}" -m conntrack --ctstate ESTABLISHED -j ACCEPT
                fi
        done
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


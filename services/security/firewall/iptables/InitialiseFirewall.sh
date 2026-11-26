#!/bin/sh
#: Name:        InitialiseFirewall.sh
#: Purpose:     Enforces baseline IPv4/IPv6 default-deny policies, loopback, conntrack states, and sweeps stray 443 rules.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialiseFirewall.sh
#:              InitialiseFirewall.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads VPCIPRANGE from configuration and provisions baseline netfilter tables once.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - /usr/sbin/iptables
#:   - /usr/sbin/ip6tables
#:   - External binaries: cat, echo, grep, cut, mkdir, touch
#:
#: Exit Codes:
#:   0          Netfilter baseline already initialized; no changes made
#:   1          Missing /home/homedir.dat, missing netfilter binaries, or initialization failure
#:   10         Kernel filter tables initialized and baseline hardened (signals ReloadFirewall.sh)
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

if [ ! -x /usr/sbin/iptables ] || [ ! -x /usr/sbin/ip6tables ]
then
        /bin/echo "Error: /usr/sbin/iptables or /usr/sbin/ip6tables not found or not executable." >&2
        exit 1
fi

ensure_v4_rule()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -A "$@"
        fi
}

ensure_v6_rule()
{
        if ! /usr/sbin/ip6tables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/ip6tables -A "$@"
        fi
}

initialised="0"
runtime_dir="${HOME}/runtime"
init_flag="${runtime_dir}/FIREWALL-INITIALISED"

if [ ! -f "${init_flag}" ]
then
        # Ensure loopback & established conntrack rules are present BEFORE setting default DROP policies
        ensure_v4_rule INPUT -i lo -j ACCEPT
        ensure_v4_rule OUTPUT -o lo -j ACCEPT
        ensure_v4_rule INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        ensure_v4_rule OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
        ensure_v4_rule FORWARD -i eth1 -o eth0 -j ACCEPT
        ensure_v4_rule INPUT -m conntrack --ctstate INVALID -j DROP

        /usr/sbin/iptables -P INPUT DROP
        /usr/sbin/iptables -P FORWARD DROP
        /usr/sbin/iptables -P OUTPUT ACCEPT

        ensure_v6_rule INPUT -i lo -j ACCEPT
        ensure_v6_rule OUTPUT -o lo -j ACCEPT

        /usr/sbin/ip6tables -P INPUT DROP
        /usr/sbin/ip6tables -P FORWARD DROP
        /usr/sbin/ip6tables -P OUTPUT ACCEPT

        set +e
        VPC_IP_RANGE="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'VPCIPRANGE')"
        set -e

        vpc_prefix=""
        if [ -n "${VPC_IP_RANGE}" ]
        then
                vpc_prefix="${VPC_IP_RANGE%/*}"
        fi

        set +e
        if [ -n "${vpc_prefix}" ]
        then
                ip_addresses="$(/usr/sbin/iptables -L INPUT -n | /bin/grep "443 ctstate" | /bin/grep -Fv "${vpc_prefix}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"
        else
                ip_addresses="$(/usr/sbin/iptables -L INPUT -n | /bin/grep "443 ctstate" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")"
        fi
        set -e

        for ip_address in ${ip_addresses}
        do
                while /usr/sbin/iptables -C INPUT -s "${ip_address}" -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1
                do
                        /usr/sbin/iptables -D INPUT -s "${ip_address}" -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                done
        done

        if [ ! -d "${runtime_dir}" ]
        then
                /bin/mkdir -p "${runtime_dir}"
        fi

        initialised="1"
        /usr/bin/touch "${init_flag}"
fi

if [ "${initialised}" = "1" ]
then
        exit 10
else
        exit 0
fi


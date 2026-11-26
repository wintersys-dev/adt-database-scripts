#!/bin/sh
#: Name:        KnickersUp.sh
#: Purpose:     Enforces default-deny IPv4/IPv6 firewall posture, loopback rules, and ICMP echo drop (KnickersUp).
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       KnickersUp.sh
#:              KnickersUp.sh [-h|--help]
#:
#: Parameters:
#:   None       Applies baseline lockdown posture once and records ${HOME}/runtime/KNICKERS_ARE_UP.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - /usr/sbin/iptables
#:   - /usr/sbin/ip6tables
#:   - External binaries: cat, echo, grep, cut, mkdir, touch
#:
#: Exit Codes:
#:   0          Lockdown posture already active; no changes made
#:   1          Missing /home/homedir.dat, missing netfilter binaries, or rule enforcement failure
#:   10         Active iptables/ip6tables chains updated with lockdown posture (signals ReloadFirewall.sh)
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

ensure_v4_insert()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -I "$@"
        fi
}

ensure_v4_append()
{
        if ! /usr/sbin/iptables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/iptables -A "$@"
        fi
}

ensure_v6_append()
{
        if ! /usr/sbin/ip6tables -C "$@" >/dev/null 2>&1
        then
                /usr/sbin/ip6tables -A "$@"
        fi
}

updated="0"
runtime_dir="${HOME}/runtime"
lockdown_flag="${runtime_dir}/KNICKERS_ARE_UP"

if [ ! -f "${lockdown_flag}" ]
then
        ensure_v4_insert INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        ensure_v4_append INPUT -p icmp -m icmp --icmp-type 8 -j DROP
        ensure_v4_append INPUT -i lo -j ACCEPT
        ensure_v4_append OUTPUT -o lo -j ACCEPT

        /usr/sbin/iptables -P INPUT DROP
        /usr/sbin/iptables -P FORWARD DROP
        /usr/sbin/iptables -P OUTPUT ACCEPT

        ensure_v6_append INPUT -i lo -j ACCEPT
        ensure_v6_append OUTPUT -o lo -j ACCEPT

        /usr/sbin/ip6tables -P INPUT DROP
        /usr/sbin/ip6tables -P FORWARD DROP
        /usr/sbin/ip6tables -P OUTPUT DROP

        if [ ! -d "${runtime_dir}" ]
        then
                /bin/mkdir -p "${runtime_dir}"
        fi

        /usr/bin/touch "${lockdown_flag}"
        updated="1"
fi

if [ "${updated}" = "1" ]
then
        exit 10
else
        exit 0
fi


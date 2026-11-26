#!/bin/sh
#: Name:        SetupFirewall.sh
#: Purpose:     Enforces Fail2Ban jails, TCP wrappers, SSH AllowUsers whitelists, and active firewall rulesets.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       SetupFirewall.sh
#:              SetupFirewall.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads BUILDMACHINEIP, SERVERUSER, SSHPORT, VPCIPRANGE, FIREWALL, FAIL2BAN, and ACTIVEFIREWALLS.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/utilities/processing/RunServiceCommand.sh
#:   - ${HOME}/services/security/config/fail2ban.conf
#:   - ${HOME}/services/security/firewall/<firewall>/*
#:   - External binaries: cat, echo, printf, grep, cut, awk, sed, mkdir, cp, rm, find, touch, sshd
#:
#: Exit Codes:
#:   0          Firewall, Fail2Ban, and SSH hardening rules applied cleanly
#:   1          Missing /home/homedir.dat, missing firewall backend, or configuration failure
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

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
style_extractor="${HOME}/utilities/config/ExtractBuildStyleValues.sh"
config_checker="${HOME}/utilities/config/CheckConfigValue.sh"
service_runner="${HOME}/utilities/processing/RunServiceCommand.sh"

set +e
BUILD_MACHINE_IP="$("${config_extractor}" 'BUILDMACHINEIP')"
SERVER_USER="$("${config_extractor}" 'SERVERUSER')"
SSH_PORT="$("${config_extractor}" 'SSHPORT')"
VPC_IP_RANGE="$("${config_extractor}" 'VPCIPRANGE')"

firewall="$("${style_extractor}" "FIREWALL" | /usr/bin/awk -F':' '{print $2}')"
fail2ban_state="$("${style_extractor}" "FAIL2BAN" | /usr/bin/awk -F':' '{print $NF}')"
set -e

# 1. Fail2Ban Jail Enforcement
if [ "${fail2ban_state}" = "active" ]
then
        if [ ! -d /etc/fail2ban/jail.d ]
        then
                /bin/mkdir -p /etc/fail2ban/jail.d
        fi

        if [ ! -f /etc/fail2ban/jail.d/jail.local ] || ! /bin/grep -q '#ADTFAIL2BAN' /etc/fail2ban/jail.d/jail.local
        then
                fail2ban_tmpl="${HOME}/services/security/config/fail2ban.conf"
                if [ ! -r "${fail2ban_tmpl}" ]
                then
                        /bin/echo "Error: Fail2Ban template missing at ${fail2ban_tmpl}" >&2
                        exit 1
                fi

                /bin/cp "${fail2ban_tmpl}" /etc/fail2ban/jail.d/jail.local
                [ -n "${SSH_PORT}" ] && /bin/sed -i "s|XXXXSSHPORTXXXX|${SSH_PORT}|g" /etc/fail2ban/jail.d/jail.local
                [ -n "${VPC_IP_RANGE}" ] && /bin/sed -i "s|#XXXXVPCIPRANGEXXXX|${VPC_IP_RANGE}|g" /etc/fail2ban/jail.d/jail.local
                [ -n "${BUILD_MACHINE_IP}" ] && /bin/sed -i "s|#XXXXBUILDMACHINEIPXXXX|${BUILD_MACHINE_IP}/32|g" /etc/fail2ban/jail.d/jail.local
                "${service_runner}" fail2ban restart
        fi
fi

# Clear active marker if firewall.dat was touched within the last minute
if [ -f "${HOME}/runtime/firewall.dat" ] && [ -n "$(/usr/bin/find "${HOME}/runtime/firewall.dat" -mmin -1 -print 2>/dev/null)" ]
then
        /bin/rm -f "${HOME}/runtime/FIREWALL-ACTIVE"
fi

if [ -f "${HOME}/runtime/FIREWALL-ACTIVE" ]
then
        exit 0
fi

# 2. Idempotent TCP Wrappers (/etc/hosts.allow & /etc/hosts.deny)
if [ -n "${VPC_IP_RANGE}" ]
then
        vpc_prefix="$(printf '%s\n' "${VPC_IP_RANGE}" | /usr/bin/awk -F'.' '{print $1 "." $2 "." $3 "."}')"
        allow_vpc="sshd : ${vpc_prefix}"
        if [ ! -f /etc/hosts.allow ] || ! /bin/grep -Fqx "${allow_vpc}" /etc/hosts.allow
        then
                /bin/echo "${allow_vpc}" >> /etc/hosts.allow
        fi
fi

if [ -n "${BUILD_MACHINE_IP}" ]
then
        allow_build="sshd : ${BUILD_MACHINE_IP}"
        if [ ! -f /etc/hosts.allow ] || ! /bin/grep -Fqx "${allow_build}" /etc/hosts.allow
        then
                /bin/echo "${allow_build}" >> /etc/hosts.allow
        fi
fi

if [ ! -f /etc/hosts.deny ] || ! /bin/grep -Fqx "ALL : ALL" /etc/hosts.deny
then
        /bin/echo "ALL : ALL" >> /etc/hosts.deny
fi

if [ "$("${config_checker}" 'ACTIVEFIREWALLS:1')" = "0" ] && [ "$("${config_checker}" 'ACTIVEFIREWALLS:3')" = "0" ]
then
        exit 0
fi

if [ -f "${HOME}/runtime/authenticator/ipaddresses.dat" ]
then
        /bin/rm -f "${HOME}/runtime/authenticator/ipaddresses.dat"
fi

# 3. Idempotent SSH AllowUsers Hardening
sshd_dropin_dir="/etc/ssh/sshd_config.d"
sshd_hardening_conf="${sshd_dropin_dir}/99-hardening.conf"
if [ ! -d "${sshd_dropin_dir}" ]
then
        /bin/mkdir -p "${sshd_dropin_dir}"
fi
if [ ! -f "${sshd_hardening_conf}" ]
then
        /usr/bin/touch "${sshd_hardening_conf}"
fi

updated_ssh="0"
if [ -n "${SERVER_USER}" ] && [ -n "${VPC_IP_RANGE}" ]
then
        allow_vpc_ssh="AllowUsers ${SERVER_USER}@${VPC_IP_RANGE}"
        if ! /bin/grep -Fq "${VPC_IP_RANGE}" /etc/ssh/sshd_config && ! /bin/grep -Fqx "${allow_vpc_ssh}" "${sshd_hardening_conf}"
        then
                /bin/echo "${allow_vpc_ssh}" >> "${sshd_hardening_conf}"
                updated_ssh="1"
        fi
fi

if [ -n "${SERVER_USER}" ] && [ -n "${BUILD_MACHINE_IP}" ]
then
        allow_build_ssh="AllowUsers ${SERVER_USER}@${BUILD_MACHINE_IP}"
        if ! /bin/grep -Fq "${BUILD_MACHINE_IP}" /etc/ssh/sshd_config && ! /bin/grep -Fqx "${allow_build_ssh}" "${sshd_hardening_conf}"
        then
                /bin/echo "${allow_build_ssh}" >> "${sshd_hardening_conf}"
                updated_ssh="1"
        fi
fi

if [ "${updated_ssh}" = "1" ]
then
        if [ -x /usr/sbin/sshd ] && ! /usr/sbin/sshd -t
        then
                /bin/echo "Error: sshd configuration test failed after updating ${sshd_hardening_conf}; skipping SSH restart to prevent lockout." >&2
                exit 1
        fi
        "${service_runner}" "ssh" restart
fi

# 4. Firewall Backend Rule Enforcement
if [ -z "${firewall}" ] || [ ! -d "${HOME}/services/security/firewall/${firewall}" ]
then
        /bin/echo "Error: Firewall driver directory missing or invalid for '${firewall}'." >&2
        exit 1
fi

firewall_dir="${HOME}/services/security/firewall/${firewall}"
updated="0"

for fw_step in \
        InitialiseFirewall.sh \
        KnickersUp.sh \
        DenyAuthenticator.sh \
        AllowCustomPorts.sh \
        AllowWireguard.sh \
        AllowBuildMachine.sh \
        AllowVPC.sh
do
        step_script="${firewall_dir}/${fw_step}"
        if [ ! -x "${step_script}" ]
        then
                /bin/echo "Error: Firewall step script missing or not executable at ${step_script}" >&2
                exit 1
        fi

        set +e
        "${step_script}"
        step_exit="$?"
        set -e

        if [ "${step_exit}" -eq 10 ]
        then
                updated="1"
        elif [ "${step_exit}" -ne 0 ]
        then
                /bin/echo "Error: ${fw_step} failed with exit code ${step_exit}." >&2
                exit 1
        fi
done

"${firewall_dir}/ReloadFirewall.sh" "${updated}"

exit 0



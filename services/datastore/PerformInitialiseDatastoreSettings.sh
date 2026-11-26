#!/bin/sh
#: Name:        PerformInitialiseDatastoreSettings.sh
#: Purpose:     Configures S3 credentials, endpoints, shell aliases, and smoke-tests s3cmd, s5cmd, or rclone.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       PerformInitialiseDatastoreSettings.sh [access_key] [secret_key] [location] [host_base] [count]
#:              PerformInitialiseDatastoreSettings.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Optional] S3 access key ID (defaults to ExtractConfigValue.sh 'S3ACCESSKEY')
#:   $2         [Optional] S3 secret access key (defaults to ExtractConfigValue.sh 'S3SECRETKEY')
#:   $3         [Optional] S3 region/location string (defaults to ExtractConfigValue.sh 'S3LOCATION')
#:   $4         [Optional] S3 endpoint hostname (defaults to ExtractConfigValue.sh 'S3HOSTBASE')
#:   $5         [Optional] Integer endpoint profile index (defaults to "1")
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckBuildStyle.sh
#:   - ${HOME}/services/datastore/init-files/s3-cfg.tmpl
#:   - ${HOME}/services/datastore/init-files/rclone-cfg.tmpl
#:   - External binaries: cat, echo, grep, cut, mkdir, cp, rm, sed, chmod, chown, awk
#:
#: Exit Codes:
#:   0          Datastore tool configured and bucket smoke-test succeeded cleanly
#:   1          Missing /home/homedir.dat, missing S3 credentials/templates, or smoke-test failure
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

log_dir="${HOME}/logs/initialbuild"
if [ ! -d "${log_dir}" ]
then
        /bin/mkdir -p "${log_dir}"
fi
MONITOR_LOG="${log_dir}/BUILD_PROCESS_MONITORING.log"

log_init_error()
{
        /bin/echo "${0} ${1}" >&2
        /bin/echo "${0} ${1}" >> "${MONITOR_LOG}" 2>/dev/null || true
}

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
style_checker="${HOME}/utilities/config/CheckBuildStyle.sh"

set +e
SERVER_USER="$("${config_extractor}" 'SERVERUSER')"

if [ -z "${1}" ]
then
        S3_ACCESS_KEY="$("${config_extractor}" 'S3ACCESSKEY')"
else
        S3_ACCESS_KEY="${1}"
fi

if [ -z "${2}" ]
then
        S3_SECRET_KEY="$("${config_extractor}" 'S3SECRETKEY')"
else
        S3_SECRET_KEY="${2}"
fi

if [ -z "${3}" ]
then
        S3_LOCATION="$("${config_extractor}" 'S3LOCATION')"
else
        S3_LOCATION="${3}"
fi

if [ -z "${4}" ]
then
        S3_HOST_BASE="$("${config_extractor}" 'S3HOSTBASE')"
else
        S3_HOST_BASE="${4}"
fi
set -e

count="${5:-1}"

if [ -z "${S3_ACCESS_KEY}" ]
then
        log_init_error "Couldn't find the S3_ACCESS_KEY setting"
        exit 1
fi

if [ -z "${S3_SECRET_KEY}" ]
then
        log_init_error "Couldn't find the S3_SECRET_KEY setting"
        exit 1
fi

if [ -z "${S3_HOST_BASE}" ]
then
        log_init_error "Couldn't find the S3_HOST_BASE setting"
        exit 1
fi

if [ -z "${S3_LOCATION}" ]
then
        log_init_error "Couldn't find the S3_LOCATION setting"
fi

# Safely escape sed replacement special characters (&, \, and delimiter |)
escape_sed_rep()
{
        printf '%s' "${1}" | /bin/sed -e 's/[\\&|]/\\&/g'
}

escaped_access="$(escape_sed_rep "${S3_ACCESS_KEY}")"
escaped_secret="$(escape_sed_rep "${S3_SECRET_KEY}")"
escaped_location="$(escape_sed_rep "${S3_LOCATION}")"
escaped_host="$(escape_sed_rep "${S3_HOST_BASE}")"

primary_host="$(printf '%s' "${S3_HOST_BASE}" | /usr/bin/awk -F'|' '{print $1}')"

# 1. Configure s3cmd (and s3fs compatibility profile)
if [ "$("${style_checker}" 'DATASTORETOOL:s3cmd')" = "1" ] || [ "$("${style_checker}" 'DATASTOREMOUNTTOOL:s3fs')" = "1" ]
then
        /bin/rm -f "${HOME}/.s3cfg-${count}" "${HOME}/.s3cfg-${count}-${count}"
        /bin/cp "${HOME}/services/datastore/init-files/s3-cfg.tmpl" "${HOME}/.s3cfg-${count}"

        /bin/sed -i "s|XXXXACCESSKEYXXXX|${escaped_access}|g" "${HOME}/.s3cfg-${count}"
        /bin/sed -i "s|XXXXSECRETKEYXXXX|${escaped_secret}|g" "${HOME}/.s3cfg-${count}"
        /bin/sed -i "s|XXXXLOCATIONXXXX|${escaped_location}|g" "${HOME}/.s3cfg-${count}"
        /bin/sed -i "s|XXXXHOSTBASEXXXX|${escaped_host}|g" "${HOME}/.s3cfg-${count}"

        if [ -f /root/.bashrc ] && ! /bin/grep -q '^alias s3cmd=' /root/.bashrc
        then
                /bin/echo "alias s3cmd='/usr/bin/s3cmd --config=/root/.s3cfg-1 --host=https://${primary_host} '" >> /root/.bashrc
        fi

        /bin/rm -f "/root/.s3cfg-${count}"
        /bin/cp "${HOME}/.s3cfg-${count}" "/root/.s3cfg-${count}"
        /bin/chmod 600 "/root/.s3cfg-${count}" "${HOME}/.s3cfg-${count}"
        [ -n "${SERVER_USER}" ] && /bin/chown "${SERVER_USER}:${SERVER_USER}" "${HOME}/.s3cfg-${count}"

        if [ "${count}" = "1" ]
        then
                /bin/cp "/root/.s3cfg-${count}" /root/.s3cfg
                /bin/chmod 600 /root/.s3cfg
        fi

        test_create="/usr/bin/s3cmd --config=/root/.s3cfg-${count} --host=https://${S3_HOST_BASE} mb s3://1$$agile"
        test_remove="/usr/bin/s3cmd --config=/root/.s3cfg-${count} --host=https://${S3_HOST_BASE} rb s3://1$$agile"
fi

# 2. Configure s5cmd
if [ "$("${style_checker}" 'DATASTORETOOL:s5cmd')" = "1" ]
then
        /bin/rm -f "${HOME}/.s5cfg-${count}"
        {
                /bin/echo "[default]"
                /bin/echo "aws_access_key_id = ${S3_ACCESS_KEY}"
                /bin/echo "aws_secret_access_key = ${S3_SECRET_KEY}"
                /bin/echo "host_base = ${S3_HOST_BASE}"
        } > "${HOME}/.s5cfg-${count}"

        if [ -f /root/.bashrc ] && ! /bin/grep -q '^alias s5cmd=' /root/.bashrc
        then
                /bin/echo "alias s5cmd='/usr/bin/s5cmd --credentials-file /root/.s5cfg-1 --endpoint-url https://${primary_host}'" >> /root/.bashrc
        fi

        /bin/rm -f "/root/.s5cfg-${count}"
        /bin/cp "${HOME}/.s5cfg-${count}" "/root/.s5cfg-${count}"
        /bin/chmod 600 "/root/.s5cfg-${count}" "${HOME}/.s5cfg-${count}"
        [ -n "${SERVER_USER}" ] && /bin/chown "${SERVER_USER}:${SERVER_USER}" "${HOME}/.s5cfg-${count}"

        if [ "${count}" = "1" ]
        then
                /bin/cp "/root/.s5cfg-${count}" /root/.s5cfg
                /bin/chmod 600 /root/.s5cfg
        fi

        test_create="/usr/bin/s5cmd --credentials-file /root/.s5cfg-${count} --endpoint-url https://${S3_HOST_BASE} mb s3://1$$agile"
        test_remove="/usr/bin/s5cmd --credentials-file /root/.s5cfg-${count} --endpoint-url https://${S3_HOST_BASE} rb s3://1$$agile"
fi

# 3. Configure rclone
if [ "$("${style_checker}" 'DATASTOREMOUNTTOOL:rclone')" = "1" ] || [ "$("${style_checker}" 'DATASTORETOOL:rclone')" = "1" ]
then
        /bin/rm -f "${HOME}/.rclone.cfg-${count}"
        /bin/cp "${HOME}/services/datastore/init-files/rclone-cfg.tmpl" "${HOME}/.rclone.cfg-${count}"

        /bin/sed -i "s|XXXXACCESSKEYXXXX|${escaped_access}|g" "${HOME}/.rclone.cfg-${count}"
        /bin/sed -i "s|XXXXSECRETKEYXXXX|${escaped_secret}|g" "${HOME}/.rclone.cfg-${count}"
        /bin/sed -i "s|XXXXLOCATIONXXXX|${escaped_location}|g" "${HOME}/.rclone.cfg-${count}"
        /bin/sed -i "s|XXXXHOSTBASEXXXX|${escaped_host}|g" "${HOME}/.rclone.cfg-${count}"

        if [ -f /root/.bashrc ] && ! /bin/grep -q '^alias rclone=' /root/.bashrc
        then
                /bin/echo "alias rclone='/usr/bin/rclone --config /root/.config/rclone/rclone.conf-1 --s3-endpoint https://${primary_host} '" >> /root/.bashrc
        fi

        /bin/mkdir -p /root/.config/rclone "${HOME}/.config/rclone"
        /bin/cp "${HOME}/.rclone.cfg-${count}" "/root/.config/rclone/rclone.conf-${count}"
        /bin/cp "${HOME}/.rclone.cfg-${count}" "${HOME}/.config/rclone/rclone.conf-${count}"
        /bin/chmod 600 "/root/.config/rclone/rclone.conf-${count}" "${HOME}/.config/rclone/rclone.conf-${count}" "${HOME}/.rclone.cfg-${count}"
        [ -n "${SERVER_USER}" ] && /bin/chown "${SERVER_USER}:${SERVER_USER}" "${HOME}/.config/rclone/rclone.conf-${count}" "${HOME}/.rclone.cfg-${count}"

        if [ "${count}" = "1" ]
        then
                /bin/cp "/root/.config/rclone/rclone.conf-${count}" /root/.config/rclone/rclone.conf
                /bin/chmod 600 /root/.config/rclone/rclone.conf
        fi

        test_create="/usr/bin/rclone --config /root/.config/rclone/rclone.conf-${count} --s3-endpoint https://${S3_HOST_BASE} mkdir s3:1$$agile"
        test_remove="/usr/bin/rclone --config /root/.config/rclone/rclone.conf-${count} --s3-endpoint https://${S3_HOST_BASE} rmdir s3:1$$agile"
fi

# Verify credential profile with a temporary bucket create/delete smoke test
if [ -n "${test_create}" ]
then
        set +e
        ${test_create} >/dev/null 2>&1
        create_exit="$?"
        ${test_remove} >/dev/null 2>&1
        remove_exit="$?"
        set -e

        if [ "${create_exit}" -ne 0 ] || [ "${remove_exit}" -ne 0 ]
        then
                log_init_error "Your datastore didn't configure correctly on this machine and that will cause the deployment to break"
                exit 1
        fi
fi

exit 0


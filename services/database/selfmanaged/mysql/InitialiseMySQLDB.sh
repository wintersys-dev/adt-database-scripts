#!/bin/sh
#: Name:        InitialiseMySQLDB.sh
#: Purpose:     Initialises a self-managed MySQL instance, creates application user/database, and applies server config.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialiseMySQLDB.sh
#:              InitialiseMySQLDB.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads DBUSERNAME, DBPASSWORD, DBNAME, IPMASK, DBPORT, and SERVERUSERPASSWORD from configuration.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/processing/RunServiceCommand.sh
#:   - ${HOME}/services/database/selfmanaged/mysql/live/mysql.sql
#:   - ${HOME}/services/database/selfmanaged/mysql/live/mysql.config
#:   - /usr/bin/mysql
#:   - External binaries: cat, echo, grep, cut, mkdir, cp, rm, sed, tr, id, sudo
#:
#: Exit Codes:
#:   0          Self-managed MySQL instance initialised and restarted cleanly
#:   1          Missing /home/homedir.dat, missing DB parameters/templates, or SQL/service failure
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
service_runner="${HOME}/utilities/processing/RunServiceCommand.sh"

set +e
IP_MASK="$("${config_extractor}" 'IPMASK')"
DB_PORT="$("${config_extractor}" 'DBPORT')"
SERVER_USER_PASSWORD="$("${config_extractor}" 'SERVERUSERPASSWORD')"

if [ -f /tmp/original_credentials.dat ]
then
        DB_U="$(/bin/grep '^DATABASE_USERNAME:' /tmp/original_credentials.dat | /usr/bin/cut -d':' -f2-)"
        DB_P="$(/bin/grep '^DATABASE_PASSWORD:' /tmp/original_credentials.dat | /usr/bin/cut -d':' -f2-)"
        DB_N="$(/bin/grep '^DATABASE_NAME:' /tmp/original_credentials.dat | /usr/bin/cut -d':' -f2-)"
        /bin/rm -f /tmp/original_credentials.dat
else
        DB_U="$("${config_extractor}" 'DBUSERNAME')"
        DB_P="$("${config_extractor}" 'DBPASSWORD')"
        DB_N="$("${config_extractor}" 'DBNAME')"
fi
set -e

# Strip any leading "<prefix>:::" qualifier if present
case "${DB_U}" in
        *::*)
                DB_U="${DB_U#*:::}"
                ;;
esac

case "${DB_P}" in
        *::*)
                DB_P="${DB_P#*:::}"
                ;;
esac

if [ -z "${DB_U}" ] || [ -z "${DB_P}" ] || [ -z "${DB_N}" ]
then
        /bin/echo "Error: Required database parameters (DBUSERNAME, DBPASSWORD, or DBNAME) are missing." >&2
        exit 1
fi

# Append archive ID suffix when initialising a restoration database
if [ -f "${HOME}/runtime/restoration_archives/ARCHIVE_ID" ]
then
        archive_id="$(/bin/cat "${HOME}/runtime/restoration_archives/ARCHIVE_ID" | /bin/sed -e 's/\./_/g' -e 's/-/_/g' | /usr/bin/tr -d '[:space:]')"
        base_db_n="$(printf '%s\n' "${DB_N}" | /bin/sed 's/_archive.*//g')"
        DB_N="${base_db_n}_${archive_id}"
fi

sql_tmpl="${HOME}/services/database/selfmanaged/mysql/live/mysql.sql"
cfg_tmpl="${HOME}/services/database/selfmanaged/mysql/live/mysql.config"

if [ ! -r "${sql_tmpl}" ] || [ ! -r "${cfg_tmpl}" ]
then
        /bin/echo "Error: MySQL initialization template files missing under ${HOME}/services/database/selfmanaged/mysql/live/" >&2
        exit 1
fi

init_dir="${HOME}/runtime/mysql-init"
if [ ! -d "${init_dir}" ]
then
        /bin/mkdir -p "${init_dir}"
fi

init_sql="${init_dir}/initialiseDB.sql"
credentials_file="${HOME}/.mysql-credentials-$$.cnf"

# Always purge temporary SQL and credential files containing plaintext passwords on exit
cleanup_sensitive_files()
{
        /bin/rm -f "${init_sql}" "${credentials_file}"
}
trap cleanup_sensitive_files EXIT INT TERM

# Escape sed replacement special characters (&, \, and delimiter |)
escape_sed_rep()
{
        printf '%s' "${1}" | /bin/sed -e 's/[\\&|]/\\&/g'
}

escaped_db_n="$(escape_sed_rep "${DB_N}")"
escaped_db_u="$(escape_sed_rep "${DB_U}")"
escaped_db_p="$(escape_sed_rep "${DB_P}")"
escaped_ip_mask="$(escape_sed_rep "${IP_MASK}")"
escaped_db_port="$(escape_sed_rep "${DB_PORT:-3306}")"

(
        umask 077
        /bin/cp "${sql_tmpl}" "${init_sql}"
        {
                /bin/echo "[client]"
                /bin/echo "password=${DB_P}"
        } > "${credentials_file}"
)

/bin/sed -i "s|XXXXDB_NXXXX|${escaped_db_n}|g" "${init_sql}"
/bin/sed -i "s|XXXXDB_UXXXX|${escaped_db_u}|g" "${init_sql}"
/bin/sed -i "s|XXXXDB_PXXXX|${escaped_db_p}|g" "${init_sql}"
/bin/sed -i "s|XXXXIP_MASKXXXX|${escaped_ip_mask}|g" "${init_sql}"

"${service_runner}" mysql start

# Attempt local auth_socket root auth first, then passworded root, then application user
set +e
/usr/bin/mysql -A -u root < "${init_sql}" >/dev/null 2>&1
init_exit="$?"

if [ "${init_exit}" -ne 0 ]
then
        /usr/bin/mysql --defaults-extra-file="${credentials_file}" -A -u root < "${init_sql}" >/dev/null 2>&1
        init_exit="$?"
fi

if [ "${init_exit}" -ne 0 ]
then
        /usr/bin/mysql --defaults-extra-file="${credentials_file}" -A -u "${DB_U}" < "${init_sql}"
        init_exit="$?"
fi
set -e

if [ "${init_exit}" -ne 0 ]
then
        /bin/echo "Error: Failed to execute MySQL initialization SQL script (exit code ${init_exit})." >&2
        exit 1
fi

if [ "$(/usr/bin/id -u)" -eq 0 ]
then
        /bin/cp "${cfg_tmpl}" /etc/mysql/my.cnf
        /bin/sed -i "s|XXXXDB_PORTXXXX|${escaped_db_port}|g" /etc/mysql/my.cnf
else
        printf '%s\n' "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /bin/cp "${cfg_tmpl}" /etc/mysql/my.cnf
        printf '%s\n' "${SERVER_USER_PASSWORD}" | /usr/bin/sudo -S /bin/sed -i "s|XXXXDB_PORTXXXX|${escaped_db_port}|g" /etc/mysql/my.cnf
fi

"${service_runner}" mysql restart

exit 0


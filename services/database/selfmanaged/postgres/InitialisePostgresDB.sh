#!/bin/sh
#: Name:        InitialisePostgresDB.sh
#: Purpose:     Initialises a self-managed PostgreSQL instance, creates application role/database, and configures pg_hba.conf.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialisePostgresDB.sh
#:              InitialisePostgresDB.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads DBUSERNAME, DBPASSWORD, DBNAME, IPMASK, and DBPORT from configuration.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/utilities/processing/RunServiceCommand.sh
#:   - ${HOME}/services/database/selfmanaged/postgres/live/postgres.psql
#:   - /usr/bin/psql
#:   - External binaries: cat, echo, grep, cut, mkdir, cp, rm, sed, tr, find, tail, sort, uniq, sudo
#:
#: Exit Codes:
#:   0          Self-managed PostgreSQL instance initialised and restarted cleanly
#:   1          Missing /home/homedir.dat, missing DB parameters/configs, or SQL/service failure
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
config_checker="${HOME}/utilities/config/CheckConfigValue.sh"
service_runner="${HOME}/utilities/processing/RunServiceCommand.sh"

set +e
IP_MASK="$("${config_extractor}" 'IPMASK')"
DB_PORT="$("${config_extractor}" 'DBPORT')"

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

IP_MASK="$(printf '%s\n' "${IP_MASK}" | /bin/sed 's/%/0/g')"
DB_PORT="${DB_PORT:-5432}"

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

if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:Postgres')" = "1" ]
then
        set +e
        postgres_config="$(/usr/bin/find /etc/postgresql -name pg_hba.conf -print 2>/dev/null | /usr/bin/tail -1)"
        [ -z "${postgres_config}" ] && postgres_config="$(/usr/bin/find / -name pg_hba.conf -print 2>/dev/null | /usr/bin/tail -1)"

        postgres_sql_config="$(/usr/bin/find /etc/postgresql -name postgresql.conf -print 2>/dev/null | /usr/bin/tail -1)"
        [ -z "${postgres_sql_config}" ] && postgres_sql_config="$(/usr/bin/find / -name postgresql.conf -print 2>/dev/null | /bin/grep etc | /usr/bin/tail -1)"
        set -e

        if [ -z "${postgres_config}" ] || [ ! -f "${postgres_config}" ] || [ -z "${postgres_sql_config}" ] || [ ! -f "${postgres_sql_config}" ]
        then
                /bin/echo "Error: Could not locate PostgreSQL configuration files (pg_hba.conf / postgresql.conf)." >&2
                exit 1
        fi

        psql_tmpl="${HOME}/services/database/selfmanaged/postgres/live/postgres.psql"
        if [ ! -r "${psql_tmpl}" ]
        then
                /bin/echo "Error: PostgreSQL initialization template missing at ${psql_tmpl}" >&2
                exit 1
        fi

        case "${DB_N}" in
                *archive*)
                        ;;
                *)
                        /bin/sed -i '/127\.0\.0\.1/d' "${postgres_config}"
                        /bin/echo "hostssl       template1              postgres            127.0.0.1/32         trust" >> "${postgres_config}"
                        ;;
        esac

        init_dir="${HOME}/runtime/postgres-init"
        if [ ! -d "${init_dir}" ]
        then
                /bin/mkdir -p "${init_dir}"
        fi

        if /bin/grep -q '_archive' "${postgres_config}"
        then
                DB_N_original="$(/bin/grep -o ' [^ ]*archive[^ ]* ' "${postgres_config}" | /usr/bin/awk '{print $1}' | /usr/bin/sort -u | /usr/bin/tail -1)"
        else
                DB_N_original="$(printf '%s\n' "${DB_N}" | /bin/sed 's/_archive.*//g')"
        fi

        DB_N="$(printf '%s\n' "${DB_N}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
        DB_N_original="$(printf '%s\n' "${DB_N_original}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
        [ -z "${DB_N_original}" ] && DB_N_original="${DB_N}"

        init_psql="${init_dir}/initialiseDB.psql"
        cleanup_temp_psql()
        {
                /bin/rm -f "${init_psql}"
        }
        trap cleanup_temp_psql EXIT INT TERM

        escape_sed_rep()
        {
                printf '%s' "${1}" | /bin/sed -e 's/[\\&|]/\\&/g'
        }

        escaped_db_n="$(escape_sed_rep "${DB_N}")"
        escaped_db_u="$(escape_sed_rep "${DB_U}")"
        escaped_db_p="$(escape_sed_rep "${DB_P}")"
        escaped_ip_mask="$(escape_sed_rep "${IP_MASK}")"

        (
                umask 077
                /bin/cp "${psql_tmpl}" "${init_psql}"
        )

        /bin/sed -i "s|XXXXDB_NXXXX|${escaped_db_n}|g" "${init_psql}"
        /bin/sed -i "s|XXXXDB_UXXXX|${escaped_db_u}|g" "${init_psql}"
        /bin/sed -i "s|XXXXDB_PXXXX|${escaped_db_p}|g" "${init_psql}"
        /bin/sed -i "s|XXXXIP_MASKXXXX|${escaped_ip_mask}|g" "${init_psql}"

        /bin/sed -i "/listen_addresses/c\        listen_addresses = '*'" "${postgres_sql_config}"
        /bin/sed -i "/^port/c\        port = ${DB_PORT}" "${postgres_sql_config}"
        /bin/sed -i "/^#port/c\        port = ${DB_PORT}" "${postgres_sql_config}"
        /bin/sed -i "/^ssl /c\        ssl = on" "${postgres_sql_config}"
        /bin/sed -i "/^#ssl /c\        ssl = on" "${postgres_sql_config}"

        "${service_runner}" postgresql restart

        set +e
        /usr/bin/sudo -u postgres /usr/bin/psql -h 127.0.0.1 -p "${DB_PORT}" template1 < "${init_psql}" >/dev/null 2>&1
        psql_exit="$?"

        if [ "${psql_exit}" -ne 0 ]
        then
                PGPASSWORD="${DB_P}" /usr/bin/psql -U "${DB_U}" -h 127.0.0.1 -p "${DB_PORT}" "${DB_N_original}" < "${init_psql}" >/dev/null 2>&1
                psql_exit="$?"
        fi

        if [ "${psql_exit}" -ne 0 ]
        then
                PGPASSWORD="${DB_P}" /usr/bin/psql -U "${DB_U}" -h 127.0.0.1 -p "${DB_PORT}" "${DB_N}" < "${init_psql}"
                psql_exit="$?"
        fi
        set -e

        if [ "${psql_exit}" -ne 0 ]
        then
                /bin/echo "Error: Failed to execute PostgreSQL initialization script (exit code ${psql_exit})." >&2
                exit 1
        fi

        if [ "${DB_N_original}" = "${DB_N}" ]
        then
                /bin/sed -i '/128/d' "${postgres_config}"
                /bin/sed -i '/template1/d' "${postgres_config}"
                /bin/sed -i "/${escaped_db_n}/d" "${postgres_config}"
                {
                        /bin/echo "hostssl       template1            ${DB_U}          127.0.0.1/32          scram-sha-256"
                        /bin/echo "hostssl       template1            ${DB_U}          ${IP_MASK}/16         scram-sha-256"
                        /bin/echo "hostssl       ${DB_N}              ${DB_U}          127.0.0.1/32          scram-sha-256"
                        /bin/echo "hostssl       ${DB_N}              ${DB_U}          ${IP_MASK}/16         scram-sha-256"
                        /bin/echo "host          ${DB_N}              ${DB_U}_notls    ${IP_MASK}/16         scram-sha-256"
                } >> "${postgres_config}"
        else
                /bin/sed -i "s|${DB_N_original}|${escaped_db_n}|g" "${postgres_config}"
        fi

        "${service_runner}" postgresql restart
fi

exit 0



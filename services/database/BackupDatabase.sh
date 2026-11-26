#!/bin/sh
#: Name:        BackupDatabase.sh
#: Purpose:     Executes engine-specific database dumps, sanitization, and archive packaging for MariaDB, MySQL, and Postgres.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       BackupDatabase.sh [output_archive]
#:              BackupDatabase.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Optional] Target .tar.gz archive path (if omitted, runs in baseline mode leaving raw SQL file)
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/utilities/processing/GetIP.sh
#:   - ${HOME}/utilities/processing/StandardiseMySQLCollations.sh
#:   - ${HOME}/services/email/SendEmail.sh
#:   - External binaries: cat, echo, grep, cut, sed, awk, wc, tar, rm, chmod, sleep, date, mariadb-dump/mysqldump/pg_dump
#:
#: Exit Codes:
#:   0          Database backup dumped, sanitized, and archived cleanly
#:   1          Missing /home/homedir.dat, aborted baseline check, or dump/archive failure
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

websiteDB="${1}"
baseline="0"
if [ -z "${websiteDB}" ]
then
        baseline="1"
fi

config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
config_checker="${HOME}/utilities/config/CheckConfigValue.sh"

set +e
if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:DBaaS')" = "1" ]
then
        HOST="$("${config_extractor}" 'DBIDENTIFIER')"
else
        HOST="$("${HOME}/utilities/processing/GetIP.sh")"
fi

DB_PORT="$("${config_extractor}" 'DBPORT')"
DB_U="$("${config_extractor}" 'DBUSERNAME')"
DB_P="$("${config_extractor}" 'DBPASSWORD')"
DB_N="$("${config_extractor}" 'DBNAME')"
IP_MASK="$("${config_extractor}" 'IPMASK')"
set -e

if [ -z "${HOST}" ] || [ -z "${DB_U}" ] || [ -z "${DB_N}" ]
then
        /bin/echo "Error: Missing required database connection parameters (HOST, DBUSERNAME, or DBNAME)." >&2
        exit 1
fi

# Escape special characters for sed search patterns and replacements
escape_sed_pat()
{
        printf '%s' "${1}" | /bin/sed -e 's/[\\.*^$[\]|]/\\&/g'
}

escape_sed_rep()
{
        printf '%s' "${1}" | /bin/sed -e 's/[\\&|]/\\&/g'
}

# 1. MariaDB / MySQL Backup Workflow
if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:Maria')" = "1" ] || \
   [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:Maria')" = "1" ] || \
   [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:MySQL')" = "1" ] || \
   [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:MySQL')" = "1" ]
then
        credentials_file="${HOME}/.mysql-credentials-$$.cnf"
        trap '/bin/rm -f "${credentials_file}"' EXIT INT TERM

        (
                umask 077
                {
                        /bin/echo "[client]"
                        /bin/echo "user=${DB_U}"
                        /bin/echo "password=${DB_P}"
                        [ -n "${DB_PORT}" ] && /bin/echo "port=${DB_PORT}"
                        /bin/echo "host=${HOST}"
                } > "${credentials_file}"
        )

        if [ -x /usr/bin/mariadb-dump ]
        then
                mysql_dump="/usr/bin/mariadb-dump --defaults-extra-file=${credentials_file} --ssl=TRUE"
        elif [ -x /usr/bin/mysqldump ]
        then
                mysql_dump="/usr/bin/mysqldump --defaults-extra-file=${credentials_file} --set-gtid-purged=OFF --ssl=TRUE --skip-column-statistics"
        else
                /bin/echo "Error: Neither mariadb-dump nor mysqldump found on system." >&2
                exit 1
        fi

        if [ -x /usr/bin/mariadb ]
        then
                mysql_cli="/usr/bin/mariadb --defaults-extra-file=${credentials_file}"
        else
                mysql_cli="/usr/bin/mysql --defaults-extra-file=${credentials_file}"
        fi

        if [ "${baseline}" = "1" ]
        then
                set +e
                table_count="$(${mysql_cli} -N -B -A "${DB_N}" -e 'SHOW TABLES;' 2>/dev/null | /usr/bin/wc -l)"
                set -e
                if [ "${table_count:-0}" -lt 10 ]
                then
                        /bin/echo "${0} $(/bin/date): There are fewer than 10 tables in the database. If this is expected enter 'Y' or 'y' (anything else to abort):"
                        read -r response
                        if [ "${response}" != "y" ] && [ "${response}" != "Y" ]
                        then
                                exit 1
                        fi
                fi
        fi

        tries=1
        dump_ok="0"
        while [ "${tries}" -le 5 ]
        do
                {
                        /bin/echo "SET SESSION sql_require_primary_key = 0;"
                        /bin/echo "DROP TABLE IF EXISTS \`zzzz\`;"
                } > ./applicationDB.sql

                set +e
                ${mysql_dump} --skip-lock-tables --single-transaction --hex-blob --routines --triggers --force -y "${DB_N}" >> ./applicationDB.sql
                dump_exit="$?"
                set -e

                /bin/sed -i \
                        -e '/SET @@SESSION\.SQL_LOG_BIN= 0;/d' \
                        -e '/SET GLOBAL INNODB_STATS_AUTO_RECALC=OFF;/d' \
                        -e '/SET GLOBAL INNODB_STATS_AUTO_RECALC=@OLD_INNODB_STATS_AUTO_RECALC;/d' \
                        -e '/SET @@GLOBAL\.GTID_PURGED=/,/;/d' \
                        -e '/SET @@GLOBAL\.GTID_PURGED=.*;/d' \
                        ./applicationDB.sql

                line_count="$(/usr/bin/wc -l < ./applicationDB.sql | /usr/bin/awk '{print $1}')"
                if [ "${dump_exit}" -eq 0 ] && [ "${line_count}" -ge 10 ]
                then
                        dump_ok="1"
                        break
                fi

                if [ "${tries}" -lt 5 ]
                then
                        /bin/sleep 10
                fi
                tries=$((tries + 1))
        done

        /bin/rm -f "${credentials_file}"
        trap - EXIT INT TERM

        if [ "${dump_ok}" != "1" ]
        then
                /bin/echo "${0} $(/bin/date): Had trouble making a backup of your database. Please investigate..." >&2
                "${HOME}/services/email/SendEmail.sh" "FAILED TO TAKE BACKUP" "I haven't been able to take a database backup, please investigate" "ERROR" || true
                exit 1
        fi

        {
                /bin/echo "DROP TABLE IF EXISTS \`zzzz\`;"
                /bin/echo "CREATE TABLE \`zzzz\` ( \`idxx\` int(10) unsigned NOT NULL, PRIMARY KEY (\`idxx\`) ) Engine=INNODB CHARSET=utf8mb4;"
        } >> ./applicationDB.sql

        if [ -n "${websiteDB}" ]
        then
                escaped_db_u="$(escape_sed_pat "${DB_U}")"
                /bin/sed -i 's|http://|https://|g' ./applicationDB.sql
                /bin/sed -i "s|${escaped_db_u}|XXXXXXXXXX|g" ./applicationDB.sql
                /bin/sed -i '/SESSION\.SQL_LOG_BIN/d' ./applicationDB.sql
                if [ -n "${IP_MASK}" ]
                then
                        escaped_ip_mask="$(escape_sed_pat "${IP_MASK}")"
                        /bin/sed -i "s|${escaped_ip_mask}|YYYYYYYYYY|g" ./applicationDB.sql
                fi
                /bin/echo "${0} $(/bin/date): Replaced all http with https in the SQL file"
                /bin/echo "${0} $(/bin/date): Tarring the database dump"
        fi

        "${HOME}/utilities/processing/StandardiseMySQLCollations.sh" ./applicationDB.sql

        if [ -n "${websiteDB}" ]
        then
                /bin/tar czf "${websiteDB}" applicationDB.sql
                /bin/rm -f ./applicationDB.sql
        fi
fi

# 2. PostgreSQL Backup Workflow
if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:Postgres')" = "1" ] || [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:Postgres')" = "1" ]
then
        if [ ! -x /usr/bin/pg_dump ]
        then
                /bin/echo "Error: /usr/bin/pg_dump not found on system." >&2
                exit 1
        fi

        /bin/echo "DROP TABLE IF EXISTS zzzz;" > ./applicationDB.psql

        set +e
        PGPASSWORD="${DB_P}" /usr/bin/pg_dump -U "${DB_U}" -h "${HOST}" -p "${DB_PORT}" -d "${DB_N}" >> ./applicationDB.psql
        pg_exit="$?"

        if [ "${pg_exit}" -ne 0 ]
        then
                /bin/echo "DROP TABLE IF EXISTS zzzz;" > ./applicationDB.psql
                /usr/bin/sudo -su postgres /usr/bin/pg_dump -h "${HOST}" -p "${DB_PORT}" -d "${DB_N}" >> ./applicationDB.psql
                pg_exit="$?"
        fi
        set -e

        if [ "${pg_exit}" -ne 0 ]
        then
                /bin/echo "${0} $(/bin/date): PostgreSQL backup failed (exit code ${pg_exit})." >&2
                "${HOME}/services/email/SendEmail.sh" "FAILED TO TAKE BACKUP" "I haven't been able to take a PostgreSQL database backup, please investigate" "ERROR" || true
                exit 1
        fi

        {
                /bin/echo "DROP TABLE IF EXISTS public.zzzz;"
                /bin/echo "CREATE TABLE public.zzzz ( idxx serial PRIMARY KEY );"
        } >> ./applicationDB.psql

        if [ -n "${websiteDB}" ]
        then
                escaped_db_u="$(escape_sed_pat "${DB_U}")"
                /bin/sed -i 's|http://|https://|g' ./applicationDB.psql
                /bin/sed -i "s|${escaped_db_u}|XXXXXXXXXX|g" ./applicationDB.psql
                if [ -n "${IP_MASK}" ]
                then
                        escaped_ip_mask="$(escape_sed_pat "${IP_MASK}")"
                        /bin/sed -i "s|${escaped_ip_mask}|YYYYYYYYYY|g" ./applicationDB.psql
                fi
                /bin/echo "${0} $(/bin/date): Replaced all http with https in the SQL file"
                /bin/echo "${0} $(/bin/date): Tarring the database dump"
                /bin/tar czf "${websiteDB}" applicationDB.psql
                /bin/rm -f ./applicationDB.psql
        fi
fi

exit 0


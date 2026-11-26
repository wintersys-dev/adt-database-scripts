#!/bin/sh
#: Name:        InitialisePostgresDB.sh
#: Purpose:     Provisions the application PostgreSQL role and target database on a Managed DBaaS instance.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialisePostgresDB.sh
#:              InitialisePostgresDB.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads DBIDENTIFIER/MYPUBLICIP, DBUSERNAME, DBPASSWORD, and DBNAME from configuration.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/utilities/config/StoreConfigValue.sh
#:   - ${HOME}/utilities/remote/ConnectToPostgresDB.sh
#:   - ${HOME}/services/database/dbaas/linode/postgres/live/postgres-user.psql
#:   - ${HOME}/services/database/dbaas/linode/postgres/live/postgres-db.psql
#:   - External binaries: cat, echo, grep, cut, mkdir, cp, rm, sed
#:
#: Exit Codes:
#:   0          DBaaS PostgreSQL role and database provisioned cleanly
#:   1          Missing /home/homedir.dat, missing DB parameters, or SQL execution failure
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
config_storer="${HOME}/utilities/config/StoreConfigValue.sh"
db_connector="${HOME}/utilities/remote/ConnectToPostgresDB.sh"

set +e
if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:DBaaS')" = "1" ]
then
        HOST="$("${config_extractor}" 'DBIDENTIFIER')"
else
        HOST="$("${config_extractor}" 'MYPUBLICIP')"
fi

DB_U="$("${config_extractor}" 'DBUSERNAME')"
DB_P="$("${config_extractor}" 'DBPASSWORD')"
DB_N="$("${config_extractor}" 'DBNAME')"
set -e

if [ -z "${HOST}" ] || [ -z "${DB_U}" ] || [ -z "${DB_P}" ] || [ -z "${DB_N}" ]
then
        /bin/echo "Error: Required database parameters (HOST, DBUSERNAME, DBPASSWORD, or DBNAME) are missing." >&2
        exit 1
fi

# Extract application role/password from "<admin>:::<app>" credential pairs using pure POSIX expansion
case "${DB_U}" in
        *::*)
                DB_U2="${DB_U#*:::}"
                ;;
        *)
                DB_U2="${DB_U}"
                ;;
esac

case "${DB_P}" in
        *::*)
                DB_P2="${DB_P#*:::}"
                ;;
        *)
                DB_P2="${DB_P}"
                ;;
esac

user_tmpl="${HOME}/services/database/dbaas/linode/postgres/live/postgres-user.psql"
db_tmpl="${HOME}/services/database/dbaas/linode/postgres/live/postgres-db.psql"

if [ ! -r "${user_tmpl}" ] || [ ! -r "${db_tmpl}" ]
then
        /bin/echo "Error: PostgreSQL initialization SQL templates missing at ${user_tmpl} / ${db_tmpl}" >&2
        exit 1
fi

init_dir="${HOME}/runtime/postgres-init"
if [ ! -d "${init_dir}" ]
then
        /bin/mkdir -p "${init_dir}"
fi

user_psql="${init_dir}/initialiseDB-user.psql"
db_psql="${init_dir}/initialiseDB.psql"

# Always purge temporary SQL files containing plaintext credentials on exit
cleanup_temp_sql()
{
        /bin/rm -f "${user_psql}" "${db_psql}"
}
trap cleanup_temp_sql EXIT INT TERM

# Escape sed replacement special characters (&, \, and delimiter |)
escape_sed_rep()
{
        printf '%s' "${1}" | /bin/sed -e 's/[\\&|]/\\&/g'
}

escaped_u2="$(escape_sed_rep "${DB_U2}")"
escaped_p2="$(escape_sed_rep "${DB_P2}")"
escaped_n="$(escape_sed_rep "${DB_N}")"
escaped_host="$(escape_sed_rep "${HOST}")"

(
        umask 077
        /bin/cp "${user_tmpl}" "${user_psql}"
        /bin/cp "${db_tmpl}" "${db_psql}"
)

/bin/sed -i "s|XXXXDB_UXXXX|${escaped_u2}|g" "${db_psql}"
/bin/sed -i "s|XXXXDB_NXXXX|${escaped_n}|g" "${db_psql}"
/bin/sed -i "s|XXXXHOSTXXXX|${escaped_host}|g" "${db_psql}"
/bin/sed -i "s|XXXXDB_UXXXX|${escaped_u2}|g" "${user_psql}"
/bin/sed -i "s|XXXXDB_PXXXX|${escaped_p2}|g" "${user_psql}"

"${db_connector}" "dbaas-init" "notraw" "defaultdb" < "${user_psql}"
"${db_connector}" "dbaas-init" "notraw" "defaultdb" < "${db_psql}"

"${config_storer}" 'DBUSERNAME' "${DB_U2}"
"${config_storer}" 'DBPASSWORD' "${DB_P2}"

exit 0
  

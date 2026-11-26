#!/bin/sh
#: Name:        InitialiseMySQLDB.sh
#: Purpose:     Provisions the application MySQL user and target database on a Linode Managed DBaaS instance.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     2.0
#:
#: Usage:       InitialiseMySQLDB.sh
#:              InitialiseMySQLDB.sh [-h|--help]
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
#:   - ${HOME}/utilities/remote/ConnectToMySQLDB.sh
#:   - ${HOME}/services/database/dbaas/linode/mysql/live/mysql-user.sql
#:   - ${HOME}/services/database/dbaas/linode/mysql/live/mysql-db.sql
#:   - External binaries: cat, echo, grep, cut, mkdir, cp, rm, sed, chmod
#:
#: Exit Codes:
#:   0          Linode DBaaS application user and database provisioned cleanly
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
db_connector="${HOME}/utilities/remote/ConnectToMySQLDB.sh"

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

# Split "<admin>:::<app>" credential pairs using pure POSIX parameter expansion
case "${DB_U}" in
        *::*)
                DB_U1="${DB_U%:::*}"
                DB_U2="${DB_U#*:::}"
                ;;
        *)
                DB_U1="${DB_U}"
                DB_U2="${DB_U}"
                ;;
esac

case "${DB_P}" in
        *::*)
                DB_P1="${DB_P%:::*}"
                DB_P2="${DB_P#*:::}"
                ;;
        *)
                DB_P1="${DB_P}"
                DB_P2="${DB_P}"
                ;;
esac

user_tmpl="${HOME}/services/database/dbaas/linode/mysql/live/mysql-user.sql"
db_tmpl="${HOME}/services/database/dbaas/linode/mysql/live/mysql-db.sql"

if [ ! -r "${user_tmpl}" ] || [ ! -r "${db_tmpl}" ]
then
        /bin/echo "Error: Linode MySQL initialization SQL templates missing under ${HOME}/services/database/dbaas/linode/mysql/live/" >&2
        exit 1
fi

init_dir="${HOME}/runtime/mysql-init"
if [ ! -d "${init_dir}" ]
then
        /bin/mkdir -p "${init_dir}"
fi

user_sql="${init_dir}/initialiseDB-user.sql"
db_sql="${init_dir}/initialiseDB.sql"

# Always ensure final application credentials are persisted and temp SQL files are purged on exit
cleanup_and_finalize()
{
        /bin/rm -f "${user_sql}" "${db_sql}"
        "${config_storer}" 'DBUSERNAME' "${DB_U2}"
        "${config_storer}" 'DBPASSWORD' "${DB_P2}"
}
trap cleanup_and_finalize EXIT INT TERM

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
        /bin/cp "${user_tmpl}" "${user_sql}"
        /bin/cp "${db_tmpl}" "${db_sql}"
)

/bin/sed -i "s|XXXXDB_UXXXX|${escaped_u2}|g" "${db_sql}"
/bin/sed -i "s|XXXXDB_NXXXX|${escaped_n}|g" "${db_sql}"
/bin/sed -i "s|XXXXHOSTXXXX|${escaped_host}|g" "${db_sql}"
/bin/sed -i "s|XXXXDB_UXXXX|${escaped_u2}|g" "${user_sql}"
/bin/sed -i "s|XXXXDB_PXXXX|${escaped_p2}|g" "${user_sql}"

# Temporarily store DBaaS admin credentials to provision user and database
"${config_storer}" 'DBUSERNAME' "${DB_U1}"
"${config_storer}" 'DBPASSWORD' "${DB_P1}"

"${db_connector}" "dbaas-init" "no" "defaultdb" < "${user_sql}"
"${db_connector}" "dbaas-init" "no" "defaultdb" < "${db_sql}"

exit 0
   

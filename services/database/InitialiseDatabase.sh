#!/bin/sh
#: Name:        InitialiseDatabase.sh
#: Purpose:     Coordinates database installation and initialisation across self-managed and DBaaS providers.
#: Author:      Peter Winter
#: Date:        26/11/2026
#: Version:     1.0
#:
#: Usage:       InitialiseDatabase.sh
#:              InitialiseDatabase.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads DATABASEINSTALLATIONTYPE, DATABASEDBaaSINSTALLATIONTYPE, and CLOUDHOST from config.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat and exported
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/CheckConfigValue.sh
#:   - ${HOME}/services/database/selfmanaged/<engine>/Initialise<Engine>DB.sh
#:   - ${HOME}/services/database/dbaas/<cloudhost>/<engine>/Initialise<Engine>DB.sh
#:   - External binaries: cat, echo, grep, cut, mkdir, touch
#:
#: Exit Codes:
#:   0          Database initialised cleanly and ${HOME}/runtime/DB_INITIALISED marker created
#:   1          Missing /home/homedir.dat, unsupported engine/provider, or driver failure
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

set +e
CLOUDHOST="$("${config_extractor}" 'CLOUDHOST')"
set -e

db_script=""

# 1. Self-managed database engines
if [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:Maria')" = "1" ]
then
        db_script="${HOME}/services/database/selfmanaged/mariadb/InitialiseMariaDB.sh"
elif [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:MySQL')" = "1" ]
then
        db_script="${HOME}/services/database/selfmanaged/mysql/InitialiseMySQLDB.sh"
elif [ "$("${config_checker}" 'DATABASEINSTALLATIONTYPE:Postgres')" = "1" ]
then
        db_script="${HOME}/services/database/selfmanaged/postgres/InitialisePostgresDB.sh"
fi

# 2. Managed DBaaS engines (MariaDB / MySQL share the mysql DBaaS driver path)
if [ -z "${db_script}" ]
then
        dbaas_engine=""
        if [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:Maria')" = "1" ] || [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:MySQL')" = "1" ]
        then
                dbaas_engine="mysql"
                dbaas_script_name="InitialiseMySQLDB.sh"
        elif [ "$("${config_checker}" 'DATABASEDBaaSINSTALLATIONTYPE:Postgres')" = "1" ]
        then
                dbaas_engine="postgres"
                dbaas_script_name="InitialisePostgresDB.sh"
        fi

        if [ -n "${dbaas_engine}" ]
        then
                case "${CLOUDHOST}" in
                        digitalocean|exoscale|linode|vultr)
                                db_script="${HOME}/services/database/dbaas/${CLOUDHOST}/${dbaas_engine}/${dbaas_script_name}"
                                ;;
                        *)
                                /bin/echo "Error: Unsupported or missing CLOUDHOST '${CLOUDHOST}' for DBaaS engine '${dbaas_engine}'." >&2
                                exit 1
                                ;;
                esac
        fi
fi

if [ -z "${db_script}" ]
then
        /bin/echo "Error: No valid self-managed or DBaaS database installation type configured." >&2
        exit 1
fi

if [ ! -x "${db_script}" ]
then
        /bin/echo "Error: Database initialisation driver missing or not executable at ${db_script}" >&2
        exit 1
fi

if ! "${db_script}"
then
        /bin/echo "Error: Database initialisation failed in ${db_script}" >&2
        exit 1
fi

if [ ! -d "${HOME}/runtime" ]
then
        /bin/mkdir -p "${HOME}/runtime"
fi

/bin/touch "${HOME}/runtime/DB_INITIALISED"
exit 0


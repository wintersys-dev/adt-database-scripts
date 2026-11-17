#!/bin/sh
#: Name:        BackupDatabaseToDatastore.sh
#: Purpose:     Exports the application database, uploads it to the distributed datastore, and verifies integrity.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       BackupDatabaseToDatastore.sh "<periodicity>" ["build-machine"]
#:              BackupDatabaseToDatastore.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Backup periodicity (hourly, daily, weekly, monthly, bimonthly, shutdown, manual)
#:   $2         [Optional] Pass "build-machine" to bypass the 300-second duplicate backup cooldown buffer
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/processing/GetIP.sh
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh
#:   - ${HOME}/services/datastore/operations/MountDatastore.sh
#:   - ${HOME}/services/datastore/operations/ListFromDatastore.sh
#:   - ${HOME}/services/datastore/operations/GetFromDatastore.sh
#:   - ${HOME}/services/datastore/operations/PutToDatastore.sh
#:   - ${HOME}/services/datastore/operations/MoveDatastoreObject.sh
#:   - ${HOME}/services/database/BackupDatabase.sh
#:   - ${HOME}/services/email/SendEmail.sh
#:   - External binaries: cat, echo, grep, cut, sed, awk, tr, date, mkdir, rm, mv, cmp, systemd-inhibit
#:
#: Exit Codes:
#:   0          Database backup completed and verified (or skipped safely due to cooldown/uninstalled state)
#:   1          Missing arguments, invalid periodicity, or inconsistent/failed backup verification
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

# Resolve the toolkit root directory from the server tracking file
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

# Validate required periodicity argument before redirecting output
if [ -z "${1}" ]
then
        /bin/echo "Error: This script requires the <Build periodicity> parameter to be set." >&2
        /bin/echo "Usage: $0 <hourly|daily|weekly|monthly|bimonthly|shutdown|manual> [build-machine]" >&2
        exit 1
fi

# Abort silently if the deployment has not completed initial installation
if [ -z "$("${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh" "config" "INSTALLED_SUCCESSFULLY")" ]
then
        exit 0
fi

machine_ip="$("${HOME}/utilities/processing/GetIP.sh")"

# Initialize backup log directory and redirect stdout/stderr to timestamped log files
log_dir="${HOME}/logs/backup"
if [ ! -d "${log_dir}" ]
then
        /bin/mkdir -p "${log_dir}"
fi

timestamp="$(/bin/date +%Y%m%d%H%M%S)"
log_file="backup_out_${timestamp}"
err_file="backup_err_${timestamp}"

/bin/echo "Log file is at: ${log_dir}/${log_file} on machine with IP address ${machine_ip}"
/bin/echo "Error file is at: ${log_dir}/${err_file} on machine with IP address ${machine_ip}"

exec 1>>"${log_dir}/${log_file}"
exec 2>>"${log_dir}/${err_file}"

# Extract deployment and database configuration values
DB_PORT="$(${HOME}/utilities/config/ExtractConfigValue.sh 'DBPORT')"
WEBSITE_URL="$(${HOME}/utilities/config/ExtractConfigValue.sh 'WEBSITEURL')"
BUILD_ARCHIVE_CHOICE="$(${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDARCHIVCECHOICE')"
CLOUDHOST="$(${HOME}/utilities/config/ExtractConfigValue.sh 'CLOUDHOST')"
MULTI_REGION="$(${HOME}/utilities/config/ExtractConfigValue.sh 'MULTIREGION')"
PRIMARY_REGION="$(${HOME}/utilities/config/ExtractConfigValue.sh 'PRIMARYREGION')"

WEBSITE_NAME="$(/bin/echo "${WEBSITE_URL}" | /usr/bin/awk -F'.' '{print $2}')"

provider_id=""
if [ "${MULTI_REGION}" = "1" ] && [ "${PRIMARY_REGION}" = "0" ]
then
        provider_id="-${CLOUDHOST}"
fi

# Normalize and validate backup periodicity
period="$(/bin/echo "${1}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
build_machine="${2}"

case "${period}" in
        hourly|daily|weekly|monthly|bimonthly|shutdown|manual)
                ;;
        *)
                /bin/echo "Error: Invalid periodicity (${period}) passed to backup script." >&2
                exit 1
                ;;
esac

bucket_suffix="${period}${provider_id}"
datastore_ops="${HOME}/services/datastore/operations"

# Ensure target backup datastore exists and check cooldown timestamp
"${datastore_ops}/MountDatastore.sh" "backup-db" "distributed" "${bucket_suffix}"

workarea_dir="${HOME}/runtime/datastore_workarea"
if [ ! -d "${workarea_dir}" ]
then
        /bin/mkdir -p "${workarea_dir}"
fi

marker_file="${workarea_dir}/time_backup_written"
/bin/rm -f "${marker_file}"

if [ -n "$("${datastore_ops}/ListFromDatastore.sh" "backup-db" "time_backup_written" "${bucket_suffix}")" ]
then
        "${datastore_ops}/GetFromDatastore.sh" "backup-db" "time_backup_written" "${workarea_dir}" "${bucket_suffix}"
fi

if [ -f "${marker_file}" ]
then
        current_time="$(/usr/bin/date +%s)"
        backup_time="$(/bin/cat "${marker_file}")"

        time_buffer="300"
        if [ "${build_machine}" = "build-machine" ]
        then
                time_buffer="0"
        fi

        elapsed="$((current_time - backup_time))"
        if [ "${elapsed}" -lt "${time_buffer}" ]
        then
                exit 0
        fi
fi

# Record updated backup timestamp marker in the datastore
/usr/bin/date +%s > "${marker_file}"
"${datastore_ops}/PutToDatastore.sh" "backup-db" "${marker_file}" "root" "distributed" "no" "${bucket_suffix}"

# Prepare clean local staging directory and export database archive
backup_dir="${HOME}/backups"
if [ ! -d "${backup_dir}" ]
then
        /bin/mkdir -p "${backup_dir}"
fi

/bin/rm -rf "${backup_dir:?}/"*
websiteDB="${backup_dir}/${WEBSITE_NAME}-DB-backup.tar.gz"

cd "${backup_dir}"
"${HOME}/services/database/BackupDatabase.sh" "${websiteDB}"
cd "${backup_dir}"

if [ ! -d "${backup_dir}/${period}" ]
then
        /bin/mkdir -p "${backup_dir}/${period}"
fi

for legacy_dump in "${backup_dir}"/*"${WEBSITE_NAME}-db"*
do
        if [ -e "${legacy_dump}" ]
        then
                /bin/mv "${legacy_dump}" "${backup_dir}/${period}/"
        fi
done

# Rotate any existing backup archive in the datastore and upload the new archive
backup_name="${WEBSITE_NAME}-DB-backup.tar.gz"

if [ -f "${websiteDB}" ]
then
        if [ -n "$("${datastore_ops}/ListFromDatastore.sh" "backup-db" "${backup_name}" "${bucket_suffix}")" ]
        then
                archive_target="${backup_name}.ARCHIVE.$(/usr/bin/date +%F-%Hhr)"
                "${datastore_ops}/MoveDatastoreObject.sh" "backup-db" "${backup_name}" "${archive_target}" "distributed" "${bucket_suffix}"
        fi

        /bin/systemd-inhibit --why="Persisting database to datastore" "${datastore_ops}/PutToDatastore.sh" "backup-db" "${websiteDB}" "root" "distributed" "no" "${bucket_suffix}"
fi

# Download the uploaded archive into a verification directory and compare byte-for-byte
verify_dir="${backup_dir}/verify"
if [ ! -d "${verify_dir}" ]
then
        /bin/mkdir -p "${verify_dir}"
else
        /bin/rm -rf "${verify_dir:?}/"*
fi

cd "${verify_dir}"
"${datastore_ops}/GetFromDatastore.sh" "backup-db" "${backup_name}" "." "${bucket_suffix}"

verification_failed="0"
if [ "${BUILD_ARCHIVE_CHOICE}" != "virgin" ]
then
        if [ ! -f "${verify_dir}/${backup_name}" ] || ! /usr/bin/cmp -s "${websiteDB}" "${verify_dir}/${backup_name}"
        then
                db_backup_label="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-db-${period}"
                /bin/echo "${0} $(/bin/date): Inconsistent backup ${db_backup_label}/${backup_name}" >&2
                "${HOME}/services/email/SendEmail.sh" "${period} database backup FAILED" "A database backup has failed (inconsistent or non existent backup)..." "ERROR"
                verification_failed="1"
        else
                /bin/echo "Backup verified as consistent"
        fi
fi

# Clean up verification artifacts and staged archive
cd "${backup_dir}"
/bin/rm -rf "${verify_dir}"
/bin/rm -f "${websiteDB}"

if [ "${verification_failed}" -ne 0 ]
then
        exit 1
fi

exit 0

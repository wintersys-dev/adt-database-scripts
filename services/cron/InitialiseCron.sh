#!/bin/sh
#: Name:        InitialiseCron.sh
#: Purpose:     Generates and installs the root crontab schedule for a database server node.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     1.0
#:
#: Usage:       InitialiseCron.sh
#:              InitialiseCron.sh [-h|--help]
#:
#: Parameters:
#:   None       Reads home directory from /home/homedir.dat and deployment settings via ExtractConfigValue.sh.
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/utilities/config/ExtractBuildStyleValues.sh
#:   - ${HOME}/utilities/config/CheckBuildStyle.sh
#:   - ${HOME}/utilities/processing/RunServiceCommand.sh
#:   - External binaries: cat, echo, grep, cut, awk, mktemp, rm, crontab, shuf, nice, sleep
#:
#: Exit Codes:
#:   0          Root crontab generated, installed, and cron service restarted cleanly
#:   1          Missing /home/homedir.dat, missing config helpers, or crontab installation failure
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
# along with The Wintersys Agile Deployment Toolkit.  If not, see <http://gnu.org>.
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

# Resolve the toolkit root directory from /home/homedir.dat
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Error: Home configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: Resolved HOME directory '${HOME}' is invalid." >&2
        exit 1
fi

# Verify required configuration helpers exist
config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
style_extractor="${HOME}/utilities/config/ExtractBuildStyleValues.sh"
style_checker="${HOME}/utilities/config/CheckBuildStyle.sh"

if [ ! -x "${config_extractor}" ] || [ ! -x "${style_extractor}" ] || [ ! -x "${style_checker}" ]
then
        /bin/echo "Error: One or more configuration helper scripts are missing or not executable under ${HOME}/utilities/config/" >&2
        exit 1
fi

# Stage the new crontab in a temporary file before installing via crontab(1)
tmp_cron="$(/bin/mktemp)"
cleanup()
{
        /bin/rm -f "${tmp_cron}"
}
trap cleanup EXIT INT TERM HUP QUIT

# Resolve timezone settings from deployment configuration
SERVER_TIMEZONE_CONTINENT="$("${config_extractor}" 'SERVERTIMEZONECONTINENT')"
SERVER_TIMEZONE_CITY="$("${config_extractor}" 'SERVERTIMEZONECITY')"

if ( [ ! -d ${HOME}/runtime/logs/crontab ] )
then
        /bin/mkdir -p ${HOME}/runtime/logs/crontab 
fi

logging=" >>${HOME}/runtime/logs/crontab/log.out 2>>${HOME}/runtime/logs/crontab/err.out "

# Write global cron environment headers
{
        /bin/echo "MAILTO=''"
        /bin/echo "HOME=${HOME}"
        if [ -n "${SERVER_TIMEZONE_CONTINENT}" ] && [ -n "${SERVER_TIMEZONE_CITY}" ]
        then
                /bin/echo "TZ=:${SERVER_TIMEZONE_CONTINENT}/${SERVER_TIMEZONE_CITY}"
        fi
} > "${tmp_cron}"

# Every minute tasks
{
        /bin/echo "*/1 * * * * ${HOME}/utilities/security/AuditSSHConnections.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/services/cron/SetupFirewallFromCron.sh ${logging}"
        /bin/echo "*/1 * * * * /bin/sleep 30 && ${HOME}/utilities/processing/UpdateIPs.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/utilities/housekeeping/RemoveExpiredLocks.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/utilities/status/MonitorForOverload.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/utilities/status/IsDatabaseUp.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/utilities/status/CheckNetworkManagerStatus.sh ${logging}"
        /bin/echo "*/1 * * * * ${HOME}/services/cron/PerformEmergencyRestorationFromCron.sh ${logging}"
} >> "${tmp_cron}"

# Every 5 minutes tasks
/bin/echo "*/5 * * * * /bin/sleep 23 && ${HOME}/services/security/firewall/MonitorFirewall.sh ${logging}" >> "${tmp_cron}"

# Every 10 minutes tasks
{
        /bin/echo "*/10 * * * * ${HOME}/utilities/security/EnforcePermissions.sh ${logging}"
        /bin/echo "*/10 * * * * ${HOME}/utilities/status/MonitorCron.sh ${logging}"
} >> "${tmp_cron}"

# Scheduled database backup tasks
{
        /bin/echo "2 * * * * ${HOME}/services/cron/BackupFromCron.sh 'hourly' ${logging}"
        /bin/echo "30 2 * * * ${HOME}/services/cron/BackupFromCron.sh 'daily' ${logging}"
        /bin/echo "30 3 * * 7 ${HOME}/services/cron/BackupFromCron.sh 'weekly' ${logging}"
        /bin/echo "30 4 1 * * ${HOME}/services/cron/BackupFromCron.sh 'monthly' ${logging}"
        /bin/echo "30 5 1 Jan,Mar,May,Jul,Sep,Nov * ${HOME}/services/cron/BackupFromCron.sh 'bimonthly' ${logging}"
} >> "${tmp_cron}"

# Daily, hourly, and maintenance tasks
{
        /bin/echo "22 4 * * * ${HOME}/utilities/software/UpdateSoftware.sh ${logging}"
        /bin/echo "44 4 * * * ${HOME}/installation/UpdateAndUpgrade.sh ${logging}"
        /bin/echo "30 3 * * * ${HOME}/utilities/housekeeping/RemoveExpiredLogs.sh ${logging}"
        /bin/echo "@hourly ${HOME}/utilities/status/LoadMonitoring.sh ${logging}"
        /bin/echo "@daily ${HOME}/utilities/housekeeping/ArchiveErrorLogs.sh ${logging}"
} >> "${tmp_cron}"

# Reboot initialization tasks
{
        /bin/echo "@reboot ${HOME}/utilities/housekeeping/CleanupAtReboot.sh ${logging}"
        /bin/echo "@reboot ${HOME}/utilities/housekeeping/RemoveExpiredLocks.sh reboot ${logging}"
        /bin/echo "@reboot ${HOME}/utilities/processing/GetIP.sh ${logging}"
        /bin/echo "@reboot ${HOME}/utilities/status/LoadMonitoring.sh 'reboot' ${logging}"
        /bin/echo "@reboot ${HOME}/utilities/status/CheckNetworkManagerStatus.sh ${logging}"
} >> "${tmp_cron}"

datastore_style="$("${style_extractor}" "DATASTORECONFIGSTYLE" | /usr/bin/awk -F':' '{print $NF}')"
case "${datastore_style}" in
        lightweight)
                /bin/echo "@reboot ${HOME}/services/datastore/config/ActivateConfigDatastoreLightweight.sh ${logging}" >> "${tmp_cron}"
                ;;
        heavyweight)
                /bin/echo "@reboot ${HOME}/services/datastore/config/ActivateConfigDatastoreHeavyweight.sh ${logging}" >> "${tmp_cron}"
                ;;
esac

# Optional scheduled virus scan based on build style
if [ "$("${style_checker}" 'VIRUSSCANNER:')" = "1" ]
then
        periodicity="$("${style_extractor}" 'VIRUSSCANNER' | /usr/bin/awk -F':' '{print $NF}')"
        case "${periodicity}" in
                daily|weekly|monthly)
                        /bin/echo "@${periodicity} /bin/sleep \$(/usr/bin/shuf -i1-1000 -n1) && /usr/bin/nice -n 15 ${HOME}/utilities/security/VirusScan.sh ${logging}" >> "${tmp_cron}"
                        ;;
        esac
fi

# Install the staged crontab safely via crontab(1)
if ! /usr/bin/crontab -u root "${tmp_cron}"
then
        /bin/echo "Error: Failed to install root crontab from staging file." >&2
        exit 1
fi

# Restart the cron daemon to apply schedule changes cleanly
service_runner="${HOME}/utilities/processing/RunServiceCommand.sh"
if [ -x "${service_runner}" ]
then
        "${service_runner}" "cron" restart
else
        /bin/echo "Error: Service runner missing or not executable at ${service_runner}" >&2
        exit 1
fi

exit 0



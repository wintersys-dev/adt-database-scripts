#!/bin/sh
#: Name:        CreateDatabaseBaseline.sh
#: Purpose:     Exports the active database, strips custom branding, and pushes a clean baseline to Git.
#: Author:      Peter Winter
#: Date:        17/11/2026
#: Version:     1.0
#:
#: Usage:       CreateDatabaseBaseline.sh ["<baseline_name>"]
#:              CreateDatabaseBaseline.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Optional] Unique baseline identifier (prompts interactively if omitted)
#:
#: Environment:
#:   HOME       Resolved automatically from /home/homedir.dat
#:
#: Dependencies:
#:   - /home/homedir.dat
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - ${HOME}/services/git/ListRepository.sh
#:   - ${HOME}/services/git/CreateRepository.sh
#:   - ${HOME}/services/git/PushToRepository.sh
#:   - ${HOME}/services/database/BackupDatabase.sh
#:   - ${HOME}/application/branding/RemoveApplicationBranding.sh
#:   - External binaries: cat, echo, grep, cut, sed, awk, tr, mkdir, rm, sleep
#:
#: Exit Codes:
#:   0          Database baseline created and pushed to remote repository successfully
#:   1          Missing config/identifier, repository conflict, or backup/push failure
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

# Ensure exported credentials are always cleared on script exit
trap 'unset REPOSITORY_TOKEN' EXIT

# Extract database credentials 
DB_U="$(${HOME}/utilities/config/ExtractConfigValue.sh 'DBUSERNAME')"
DB_P="$(${HOME}/utilities/config/ExtractConfigValue.sh 'DBPASSWORD')"
DB_N="$(${HOME}/utilities/config/ExtractConfigValue.sh 'DBNAME')"
DB_PORT="$(${HOME}/utilities/config/ExtractConfigValue.sh'DBPORT')"

# Determine interactive vs. non-interactive baseline identifier
if [ -z "${1}" ]
then
        interactive_mode="1"
        application_type="$("${extract_cfg}" 'APPLICATION')"
        /bin/echo "Your application type is set to: ${application_type}"
        /bin/echo "Please make very sure this is correct for your application otherwise things will break."
        /bin/echo "Press <enter> when you are sure:"
        read -r dummy

        /bin/echo "Please enter a unique identifier for your baseline (target repo: <identifier>-db-baseline):"
        read -r baseline_name
else
        interactive_mode="0"
        baseline_name="${1}"
fi

if [ -z "${baseline_name}" ]
then
        /bin/echo "Error: Baseline identifier cannot be blank." >&2
        exit 1
fi

target_repo="${baseline_name}-db-baseline"
/bin/echo "Creating baseline of your database (${target_repo})..."

# Extract website and repository configuration values
WEBSITE_URL="$("${extract_cfg}" 'WEBSITEURL')"
WEBSITE_DISPLAY_NAME="$("${extract_cfg}" 'WEBSITEDISPLAYNAME' | /bin/sed 's/_/ /g')"

WEBSITE_NAME="$(/bin/echo "${WEBSITE_URL}" | /usr/bin/awk -F'.' '{print $2}')"
ROOT_DOMAIN="$(/bin/echo "${WEBSITE_URL}" | /usr/bin/cut -d'.' -f2-)"
WEBSITE_DISPLAY_NAME_UPPER="$(/bin/echo "${WEBSITE_DISPLAY_NAME}" | /bin/sed 's/_/ /g' | /usr/bin/tr '[:lower:]' '[:upper:]')"
WEBSITE_DISPLAY_NAME_LOWER="$(/bin/echo "${WEBSITE_DISPLAY_NAME}" | /bin/sed 's/_/ /g' | /usr/bin/tr '[:upper:]' '[:lower:]')"

APPLICATION_REPOSITORY_PROVIDER="$("${extract_cfg}" 'APPLICATIONREPOSITORYPROVIDER')"
APPLICATION_REPOSITORY_USERNAME="$("${extract_cfg}" 'APPLICATIONREPOSITORYUSERNAME')"
#APPLICATION_REPOSITORY_TOKEN="$("${extract_cfg}" 'APPLICATIONREPOSITORYTOKEN')"
APPLICATION_REPOSITORY_OWNER="$("${extract_cfg}" 'APPLICATIONREPOSITORYOWNER')"

# Prepare clean staging directory for the baseline dump
backup_dir="${HOME}/backups/${baseline_name}"
if [ ! -d "${backup_dir}" ]
then
        /bin/mkdir -p "${backup_dir}"
fi

cd "${backup_dir}"

if [ -d "${HOME}/.git" ]
then
        /bin/rm -rf "${HOME}/.git"
fi

# Verify or provision the target remote baseline repository
export REPOSITORY_TOKEN="${APPLICATION_REPOSITORY_TOKEN}"

repo_status="$("${HOME}/services/git/GitListRepository.sh" "${APPLICATION_REPOSITORY_PROVIDER}" "${APPLICATION_REPOSITORY_OWNER}" "${target_repo}" "${APPLICATION_REPOSITORY_USERNAME}")"

case "${repo_status}" in
        none)
                create_repo="0"
                if [ "${interactive_mode}" = "1" ]
                then
                        /bin/echo "Repository (${target_repo}) not found. Do you want me to create one? (Y/y):"
                        read -r response
                        case "${response}" in
                                [Yy])
                                        create_repo="1"
                                        ;;
                                *)
                                        /bin/echo "Aborting baseline creation."
                                        unset REPOSITORY_TOKEN
                                        exit 0
                                        ;;
                        esac
                else
                        create_repo="1"
                fi

                if [ "${create_repo}" = "1" ]
                then
                        /bin/echo "Creating new repository (${target_repo})..."
                        "${HOME}/services/git/CreateRepository.sh" "${APPLICATION_REPOSITORY_PROVIDER}" "${target_repo}" "${APPLICATION_REPOSITORY_USERNAME}"
                        # Allow remote provider API propagation cooldown
                        /bin/sleep 10

                        verify_status="$("${HOME}/services/git/ListRepository.sh" "${APPLICATION_REPOSITORY_PROVIDER}" "${APPLICATION_REPOSITORY_OWNER}" "${target_repo}" "${APPLICATION_REPOSITORY_USERNAME}")"
                        if [ "${verify_status}" = "empty" ]
                        then
                                /bin/echo "Repository (${target_repo}) successfully created."
                                if [ "${interactive_mode}" = "1" ]
                                then
                                        /bin/echo "Press <enter> to continue:"
                                        read -r dummy
                                fi
                        else
                                /bin/echo "Error: Repository (${target_repo}) was not created or is unreachable. Exiting." >&2
                                unset REPOSITORY_TOKEN
                                exit 1
                        fi
                fi
                ;;
        empty)
                /bin/echo "Suitable empty repository (${target_repo}) found."
                if [ "${interactive_mode}" = "1" ]
                then
                        /bin/echo "Press <enter> to continue:"
                        read -r dummy
                fi
                ;;
        full)
                /bin/echo "Error: Repository (${target_repo}) already exists and is not empty. Please empty, delete, or rename it before rerunning." >&2
                unset REPOSITORY_TOKEN
                exit 1
                ;;
        *)
                /bin/echo "Error: Unexpected repository status (${repo_status}) returned for ${target_repo}." >&2
                unset REPOSITORY_TOKEN
                exit 1
                ;;
esac

unset REPOSITORY_TOKEN

"${HOME}/services/database/BackupDatabase.sh"
"${HOME}/application/branding/RemoveApplicationBranding.sh"

# Push baseline artifacts to the remote Git repository
export REPOSITORY_TOKEN="${APPLICATION_REPOSITORY_TOKEN}"
set +e
"${HOME}/services/git/PushToRepository.sh" "${APPLICATION_REPOSITORY_PROVIDER}" "${APPLICATION_REPOSITORY_OWNER}" "${target_repo}" "${APPLICATION_REPOSITORY_USERNAME}"
error_code="$?"
set -e
unset REPOSITORY_TOKEN

# Clean up temporary staging workspace
cd "${HOME}"
if [ -d "${backup_dir}" ]
then
        /bin/rm -rf "${backup_dir}"
fi

if [ "${error_code}" -ne 0 ]
then
        /bin/echo "Error: Failed to push baseline to ${target_repo}. Verify your application repository authorisation token." >&2
        exit 1
fi

/bin/echo ""
/bin/echo "========================================================================================================================================="
/bin/echo "Baseline complete. Verify repository ${target_repo} on ${APPLICATION_REPOSITORY_PROVIDER} for user: ${APPLICATION_REPOSITORY_USERNAME}"
/bin/echo "========================================================================================================================================="

exit 0

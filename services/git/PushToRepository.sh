#!/bin/sh
##################################################################################
# SCRIPT      : PushToRepository.sh
# AUTHOR      : Peter Winter
# DATE        : 25/10/2026
# VERSION     : 1.0.0
# DESCRIPTION : This script initializes a local Git workspace, sets the default 
#               branch to main, stages all files including the .gitattributes, 
#               and pushes a baseline commit to a remote repository provider.
#               It handles dynamic URL resolution and secure .netrc authentication.
#
# INTERFACE   : $0 <repository_provider> <repository_owner> <repository_name> [repository_username]
#
# PARAMETERS  :
#   $1 - repository_provider : Hosting vendor string (e.g., github, gitlab)
#   $2 - repository_owner    : Organization or profile namespace account name
#   $3 - repository_name     : Case-sensitive project target repository name
#   $4 - repository_username : Account user profile identity for auth configuration
#
# ENVIRONMENT VARIABLES:
#   - REPOSITORY_TOKEN       : Must be exported in the shell for authentication
#
# CONFIGURATION DEPENDENCIES:
#   - /home/homedir.dat      : Must contain absolute path to user home directory
#   - ${HOME}/.netrc         : Managed temporarily during runtime (Chmod 600)
#   - URL Endpoint           : ${HOME}/services/git/<provider>/GetProviderURL.sh
#######################################################################################
# License Agreement:
# This file is part of The Agile Deployment Toolkit.
# The Agile Deployment Toolkit is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# The Agile Deployment Toolkit is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with The Agile Deployment Toolkit.  If not, see <http://www.gnu.org/licenses/>.
#####################################################################################
#####################################################################################
#set -x
set -e

HOME="`/bin/cat /home/homedir.dat`"

if ( [ "${1}" = "" ] || [ "${2}" = "" ] || [ "${3}" = "" ] )
then
        /bin/echo "Error: 3 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <repository_provider> <repository_owner> <repository_name> [repository_username]"
        exit 1
fi

repository_provider="${1}"
repository_owner="${2}"
repository_name="${3}"
repository_username="${4}"


cat << EOF > ${HOME}/.netrc
machine github.com
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF

#I only use the .netrc file for git commands and I construct it and remove it every time I want to use it
#if I need a .netrc file for curl (for example) I construct a custom file name and use the custom file so there is no clash
chmod 600 ${HOME}/.netrc

handle_exit() {
        exit_status=$?

        if ( [ "$exit_status" -ne "0" ] )
        then
                echo "Error: Script ($0) aborted unexpectedly with status $exit_status" >&2
        fi
        rm -f "${HOME}/.netrc"
}

trap handle_exit EXIT

/usr/bin/git init
/usr/bin/git branch -M main
provider_url="`${HOME}/services/git/${repository_provider}/GetProviderURL.sh`"
/usr/bin/git remote add origin https://${provider_url}/${repository_owner}/${repository_name}
/usr/bin/git add .gitattributes
/usr/bin/git add --all -f
/usr/bin/git commit -m "Baseline Baby"
/usr/bin/git push -u origin main

#!/bin/sh
##################################################################################
# SCRIPT      : CreateRepository.sh
# AUTHOR      : Peter Winter
# DATE        : 13/07/2021
# VERSION     : 1.0.0
# DESCRIPTION : This script acts as an validates and orchestrates repository creation
#               requests to the designated platform-specific implementation.
#
# INTERFACE   : $0 <provider> <repo_name> <auth_username>
#
# PARAMETERS  :
#   $1 - repository_provider  : Hosting vendor string (e.g., github, gitlab)
#   $2 - repository_name      : Name string of the target repository to create
#   $3 - repository_username  : Administrative account username for authentication
#
# CONFIGURATION DEPENDENCIES:
#   - Sub-driver wrapper path : ${HOME}/services/git/<provider>/CreateRepository.sh
#######################################################################################################
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
#######################################################################################################
#######################################################################################################
#set -x
set -e

HOME="`/bin/cat /home/homedir.dat`"

if ( [ "${1}" = "" ] || [ "${2}" = "" ] )
then
        /bin/echo "Error: 2 arguments are required and 1 optional argumment"
        /bin/echo "Usage: $0 <repository_provider> <repository_name> [repository_username]"
        exit 1
fi

repository_provider="${1}"
repository_name="${2}"
repository_username="${3}"

${HOME}/services/git/${repository_provider}/CreateRepository.sh  "${repository_username}" "${repository_name}" 

if ( [ "$?" != "0" ] )
then
        /bin/echo "CreateRepository.sh exited with an error code"
        exit 1
fi

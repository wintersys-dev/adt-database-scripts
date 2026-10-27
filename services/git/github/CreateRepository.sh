#!/bin/sh
##################################################################################
# SCRIPT      : CreateRepository.sh (GitHub Provider)
# AUTHOR      : Peter Winter
# DATE        : 13/07/2021
# VERSION     : 1.0.0
# DESCRIPTION : This script programmatically creates a new private repository on 
#               GitHub via its REST API using curl. It manages a temporary 
#               `.netrc` file locally to authenticate the API request securely.
#
# INTERFACE   : $0 <auth_username> <repo_name>
#
# PARAMETERS  :
#   $1 - repository_username  : Administrative GitHub username profile identification
#   $2 - repository_name      : The string name of the target repository to initialize
#
# ENVIRONMENT VARIABLES:
#   - REPOSITORY_TOKEN        : Must be exported in the shell for API authentication
#
# CONFIGURATION DEPENDENCIES:
#   - ${HOME}/.netrc          : Managed temporarily during runtime (Chmod 600)
#
# LICENSE AGREEMENT:
#   This file is part of The Agile Deployment Toolkit.
#   Licensed under the GNU General Public License v3 or later.
# ################################################################################

######################################################################################################
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

repository_username="${1}"
repository_name="${2}"

cat << EOF > ${HOME}/.netrc
machine api.github.com
login ${repository_username}
password ${REPOSITORY_TOKEN}
EOF

#I only use the .netrc file for git commands and I construct it and remove it every time I want to use it
#if I need a .netrc file for curl (for example) I construct a custom file name and use the custom file so there is no clash
chmod 600 ${HOME}/.netrc

/usr/bin/curl --netrc https://api.github.com/user/repos -d '{"name":"'${repository_name}'","private":"true"}'

error_code="$?"
/bin/rm ${HOME}/.netrc

if ( [ "${error_code}" != "0" ] )
then
        status "curl request to api.github.com/user/repos exited with error code ${error_code}"
        exit 1
fi

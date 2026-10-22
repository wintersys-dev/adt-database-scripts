#!/bin/sh

branch_command="${1}"
repository_provider="${2}"
authentication_token="${3}"
repository_username="${4}"
repository_ownername="${5}"
repository_name="${6}"
destination_directory="${7}"

/usr/bin/git clone --depth 1 ${branch_command} https://${repository_username}${authentication_token}@bitbucket.org/${repository_ownername}/${repository_name}.git  ${destination_directory}

#!/bin/sh 
####################################################################################
# Tool/Script: Context-Aware S3 Datastore File Deletion and Purging Utility
# Author:      Peter Winter
# Date :       9/4/2021
# Suite:       The Agile Deployment Toolkit
# 
# Description: This script automates individual file deletion tasks across multi-mode
#              cloud datastores. It dynamically constructs naming topologies for target S3
#              buckets based on specific bucket classifications and appends the path 
#              to the target file. It propagates the execution to an underlying execution
#              engine script in either "local" (single region) or "distributed" (multi-node) 
#              deployment topologies.
#
# Arguments:
#              $1 - <bucket_type>            : Target category classification. 
#              $2 - <file_to_delete>         : The specific file name or relative object pathway to purge.
#              $3 - <mode>                   : Topology routine selection. Valid values:
#                                              "local"       -> Single target datastore evaluation.
#                                              "distributed" -> Multi-token configuration fanout loop.
#              $4 - [additional_specifier]   : Optional contextual tracking suffix string used for 
#                                              asset paths, target sub-directories, or unique node tags.
#
# Environmental Dependencies:
#              - /home/buildhome.dat containing valid application root pathway tracking string.
#              - Toolkit helpers: GetVariableValue.sh script infrastructure for variable evaluations.
#              - Environment registers: S3_ACCESS_KEY, WEBSITE_URL, DNS_CHOICE, SERVER_USER, 
#                                       SSL_GENERATION_SERVICE configuration states.
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
# along with The Agile Deployment Toolkit.  If not, see <http://gnu.org>.
######################################################################################
######################################################################################
#set -x
set -e

HOME="`/bin/cat /home/homedir.dat`"

if ( [ "${1}" = "" ] || [ "${2}" = "" ] || [ "${3}" = "" ] )
then
        /bin/echo "Error: 3 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <bucket_type> <file_to_delete> <mode> <additional_specifier>"
        exit 1
fi

bucket_type="${1}"
file_to_delete="${2}"
mode="${3}"
additional_specifier="${4}"

WEBSITE_URL="`${HOME}/utilities/config/ExtractConfigValue.sh 'WEBSITEURL'`"
SERVER_USER="`${HOME}/utilities/config/ExtractConfigValue.sh 'SERVERUSER'`"
DNS_CHOICE="`${HOME}/utilities/config/ExtractConfigValue.sh 'DNSCHOICE'`"

TOKEN="`/bin/echo ${SERVER_USER} | /usr/bin/fold -w 4 | /usr/bin/head -n 1 | /usr/bin/tr '[:upper:]' '[:lower:]'`"

if ( [ "${bucket_type}" = "multi-region" ] )
then
        active_bucket="`/bin/echo ${WEBSITE_URL} | /bin/sed 's/\./-/g'`-multi-region"
elif ( [ "${bucket_type}" = "config-sync" ] )
then
        active_bucket="`/bin/echo ${WEBSITE_URL} | /bin/sed 's/\./-/g'`-config-sync-tunnel`/bin/echo ${additional_specifier} | /bin/sed 's:/:-:g'`"
elif ( [ "${bucket_type}" = "config" ] )
then
        active_bucket="`/bin/echo "${WEBSITE_URL}"-config | /bin/sed 's/\./-/g'`-${TOKEN}"
elif ( [ "${bucket_type}" = "backup" ] )
then
        active_bucket="`/bin/echo ${WEBSITE_URL} | /bin/sed 's/\./-/g'`-db-${additional_specifier}"
elif ( [ "${bucket_type}" = "auth" ] )
then
        active_bucket="authip-adt-allowed-${additional_specifier}"
elif ( [ "${bucket_type}" = "dbaas" ] )
then
        active_bucket="`/bin/echo ${WEBSITE_URL} | /bin/sed 's/\./-/g'`"
        active_bucket="${active_bucket}-${DNS_CHOICE}-dbaas"
elif ( [ "${bucket_type}" = "snap" ] )
then
        active_bucket="`/bin/echo ${WEBSITE_URL} | /bin/sed 's/\./-/g'`"
        active_bucket="${active_bucket}-${DNS_CHOICE}-snap"
fi

DATASTORE_TOOL="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "DATASTORETOOL" | /usr/bin/awk -F':' '{print $2}'`"
S3_ACCESS_KEY="`${HOME}/utilities/config/ExtractConfigValue.sh 'S3ACCESSKEY'`"
no_tokens="`/bin/echo "${S3_ACCESS_KEY}" | /usr/bin/fgrep -o '|' | /usr/bin/wc -l`"
no_tokens="`/usr/bin/expr ${no_tokens} + 1`"
count="1"

if ( [ "${mode}" = "local" ] )
then
        ${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformDeleteFromDatastore.sh ${active_bucket}/${file_to_delete} ${count}
elif ( [ "${mode}" = "distributed" ] )
then
        while ( [ "${count}" -le "${no_tokens}" ] )
        do
                ${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformDeleteFromDatastore.sh ${active_bucket}/${file_to_delete} ${count}
                count="`/usr/bin/expr ${count} + 1`"
        done
fi

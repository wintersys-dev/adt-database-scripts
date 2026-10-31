#!/bin/sh
###################################################################################
# @file        PutToDatastore.sh
# @brief       Context-Aware S3 Datastore Object & Asset Upload Utility.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script automates uploading individual files or asset directories 
#              to managed cloud datastores. It dynamically constructs naming 
#              topologies for target S3 buckets based on specific system profiles. It passes the 
#              payload to an underlying script execution engine with an optional 
#              post-upload deletion flag, executing either against a standalone primary 
#              endpoint ("local") or propagating sequentially across multi-node 
#              distributed regional clusters ("distributed").
#
# @param       $1  [Required] The target category classification bucket type string.
# @param       $2  [Required] Absolute or relative local pathway of the file to upload.
# @param       $3  [Required] Target destination folder path within the bucket. Passing "root" resets this to an empty base value.
# @param       $4  [Required] Topology routine selection ("local" or "distributed").
# @param       $5  [Required] Operational switch flag indicating whether to purge the local source file after a success.
# @param       $6  [Optional] Contextual tracking suffix string used for asset paths, target sub-directories, or unique node tags.
#
# @env         HOME                    Sourced application root tracking pathway string.
# @env         S3_ACCESS_KEY           Access token configurations used for fanout loops.
# @env         WEBSITE_URL             Primary base domain identifier mapping out schemas.
# @env         DNS_CHOICE              Configuration flag used to tag platform routing options.
# @env         SSL_GENERATION_SERVICE  Target backend token logic router (LETSENCRYPT/ZEROSSL).
# @env         SERVER_USER             Base tracking string used to generate local tokens.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh system service wrapper infrastructure for lookup evaluations.
#              - ExtractBuildStyleValues.sh configuration parser for active software parameters.
#              - PerformPutToDatastore.sh data ingest driver selected by software parameters.
#
# @security    
#              - Requires isolation of S3_ACCESS_KEY environment arrays containing active tokens.
#              - Forces a static "no" delete state during distributed loops to prevent race conditions or premature file wiping.
#              - Relies on system-owned executable paths (/bin, /usr/bin) to circumvent hijack exploits.
#
# @exit        0  Success: Local binary/payload securely delivered to targeted datastore nodes.
# @exit        1  Failure: Missing arguments or downstream upload driver runtime faults.
###################################################################################
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

# Sourced application root tracking pathway string
if [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
else
        /bin/echo "Application root configuration file missing at /home/homedir.dat" >&2
        exit 1
fi

# Ensure logging directory structure exists safely
if [ ! -d "${HOME}/runtime/logs/datastore" ]
then
        /bin/mkdir -p "${HOME}/runtime/logs/datastore"
fi

# Define log file destination path
LOG_FILE="${HOME}/runtime/logs/datastore/PutToDatastore.log"

# Unified error reporting handler that writes to syslog/log file and stderr
log_error()
{
        error_msg="[$(/bin/date '+%Y-%m-%d %H:%M:%S')] ERROR: ${1}"
        /bin/echo "${error_msg}" >&2
        
        # Safe append to log file if write access is permitted
        if [ -w "${LOG_FILE}" ] || [ -w "$(/usr/bin/dirname "${LOG_FILE}")" ]
        then
                /bin/echo "${error_msg}" >> "${LOG_FILE}"
        fi
}

# Input validation
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ] || [ -z "${4}" ] || [ -z "${5}" ]
then
        log_error "5 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <bucket_type> <file_to_put> <place_to_put> <mode> <delete> <additional_specifier>" >&2
        exit 1
fi

bucket_type="${1}"
file_to_put="${2}"
place_to_put="${3}"
mode="${4}"
delete="${5}"
additional_specifier="${6}"

# Determine context paths safely
HOSTNAME_VAL="$(/usr/bin/hostname)"
if /bin/echo "${HOSTNAME_VAL}" | /bin/grep -q '\-auth-'
then
        WEBSITE_URL="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'AUTHSERVERURL')"
        DNS_CHOICE="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'AUTHDNSCHOICE')"
else
        WEBSITE_URL="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'WEBSITEURL')"
        DNS_CHOICE="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'DNSCHOICE')"
fi

SSL_GENERATION_SERVICE="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'SSLGENERATIONSERVICE')"
SERVER_USER="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'SERVERUSER')"

# Safely extract a 4-character lowercase token from SERVER_USER without breaking execution pipelines
TOKEN="$(/bin/echo "${SERVER_USER}" | /usr/bin/fold -w 4 | /usr/bin/head -n 1 | /usr/bin/tr '[:upper:]' '[:lower:]')"

# Helper transformation: Replace dots with hyphens securely
url_hyphenated="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')"

# Initialize bucket string tracking
active_bucket=""

case "${bucket_type}" in
        "ssl")
                service_token=""
                if [ "${SSL_GENERATION_SERVICE}" = "LETSENCRYPT" ]
                then
                        service_token="lets"
                elif [ "${SSL_GENERATION_SERVICE}" = "ZEROSSL" ]
                then
                        service_token="zero" 
                fi
                active_bucket="${url_hyphenated}-${DNS_CHOICE}-${service_token}-ssl"
                ;;
        "multi-region")
                active_bucket="${url_hyphenated}-multi-region"
                ;;
        "webroot-sync")
                specifier_sanitized="$(/bin/echo "${additional_specifier}" | /bin/sed 's:/:-:g')"
                active_bucket="${url_hyphenated}-webroot-sync-tunnel${specifier_sanitized}"
                ;;
        "config-sync")
                specifier_sanitized="$(/bin/echo "${additional_specifier}" | /bin/sed 's:/:-:g')"
                active_bucket="${url_hyphenated}-config-sync-tunnel${specifier_sanitized}"
                ;;
        "config")
                active_bucket="$(/bin/echo "${WEBSITE_URL}-config" | /bin/sed 's/\./-/g')-${TOKEN}"
                ;;
        "asset")
                active_bucket="$(/bin/echo "${WEBSITE_URL}-assets-${additional_specifier}" | /bin/sed -e 's/\./-/g' -e 's;/;-;g' -e 's/--/-/g')"
                ;;
        "backup")
                active_bucket="${url_hyphenated}-${additional_specifier}"
                ;;
        "auth")
                active_bucket="authip-adt-allowed-${additional_specifier}"
                ;;
        "dbaas")
                active_bucket="${url_hyphenated}-${DNS_CHOICE}-dbaas"
                ;;
        "snap")
                active_bucket="${url_hyphenated}-${DNS_CHOICE}-snap"
                ;;
        "firewall-auth-laptop-ips"|"firewall-emailed-links"|"whitelist-auth-laptop-ips"|"whitelist-emailed-links"|"basic-auth-credentials"|"wire-guard"|"wire-guard-emails"|"wire-guard-emailed-links")
                if /bin/echo "${HOSTNAME_VAL}" | /bin/grep -q '\-auth-'
                then
                        WEBSITE_URL_ALT="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'WEBSITEURLORIGINAL')"
                else
                        WEBSITE_URL_ALT="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'WEBSITEURL')"
                fi
                url_hyphenated_alt="$(/bin/echo "${WEBSITE_URL_ALT}" | /bin/sed 's/\./-/g')"
                
                if [ "${bucket_type}" = "firewall-auth-laptop-ips" ]
                then
                        active_bucket="${url_hyphenated_alt}-firewall-auth-laptop-ips"
                elif [ "${bucket_type}" = "firewall-emailed-links" ]
                then
                        active_bucket="${url_hyphenated_alt}-firewall-emailed-links"
                elif [ "${bucket_type}" = "whitelist-auth-laptop-ips" ]
                then
                        active_bucket="${url_hyphenated_alt}-whitelist-auth-laptop-ips"
                elif [ "${bucket_type}" = "whitelist-emailed-links" ]
                then
                        active_bucket="${url_hyphenated_alt}-whitelist-emailed-links"
                elif [ "${bucket_type}" = "basic-auth-credentials" ]
                then
                        active_bucket="${url_hyphenated_alt}-basic-auth-credentials"
                elif [ "${bucket_type}" = "wire-guard" ]
                then
                        active_bucket="${url_hyphenated_alt}-wireguard"
                elif [ "${bucket_type}" = "wire-guard-emails" ]
                then
                        active_bucket="${url_hyphenated_alt}-wireguard-emails"
                elif [ "${bucket_type}" = "wire-guard-emailed-links" ]
                then
                        active_bucket="${url_hyphenated_alt}-wireguard-emailed-links"
                fi
                ;;
        "ad-hoc")
                active_bucket="${additional_specifier}"
                ;;
esac

# Ensure a bucket parsing rule matched
if [ -z "${active_bucket}" ]
then
        log_error "Invalid bucket type specified or failed to build naming topology."
        exit 1
fi

DATASTORE_TOOL="$("${HOME}/utilities/config/ExtractBuildStyleValues.sh" "DATASTORETOOL" | /usr/bin/awk -F':' '{print $2}')"
S3_ACCESS_KEY="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'S3ACCESSKEY')"

# Safely compute token counts
no_tokens="$(/bin/echo "${S3_ACCESS_KEY}" | /usr/bin/fgrep -o '|' | /usr/bin/wc -l)"
no_tokens="$(/usr/bin/expr "${no_tokens}" + 1)"

count="1"
execution_driver="${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformPutToDatastore.sh"

# Execution handling with wrapped defensive boundaries
if [ "${mode}" = "local" ]
then
        "${execution_driver}" "${file_to_put}" "${active_bucket}/${place_to_put}" "${delete}" "${count}"
elif [ "${mode}" = "distributed" ]
then
        while [ "${count}" -le "${no_tokens}" ]
        do
                "${execution_driver}" "${file_to_put}" "${active_bucket}/${place_to_put}" "no" "${count}"
                count="$(/usr/bin/expr "${count}" + 1)"
        done
else
        log_error "Invalid routine mode '${mode}'. Must be 'local' or 'distributed'."
        exit 1
fi

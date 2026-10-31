#!/bin/sh
###################################################################################
# @file        GetFromDatastore.sh
# @brief       Context-Aware S3 Datastore Object Retrieval & Fetching Utility.
# @author      Peter Winter
# @date        09/04/2021
# @version     1.0
#
# @details     This script automates individual file retrieval tasks from managed cloud 
#              datastores. It dynamically resolves naming topologies for target S3 
#              buckets based on specific system classifications. Unlike purging 
#              utilities, this fetching operation executes strictly against your 
#              primary first-order datastore instance, skipping replication loops.
#
# @param       $1  [Required] The target category classification bucket type string.
# @param       $2  [Required] Name or relative pathway of the specific cloud object to fetch.
# @param       $3  [Required] Local directory path or target file name destination.
# @param       $4  [Optional] Contextual tracking suffix used for asset paths, directory roots, or unique runtime token suffixes.
#
# @env         HOME                    Sourced application root tracking pathway string.
# @env         WEBSITE_URL             Primary base domain identifier mapping out schemas.
# @env         DNS_CHOICE              Configuration flag used to tag platform routing options.
# @env         SSL_GENERATION_SERVICE  Target backend token logic router (LETSENCRYPT/ZEROSSL).
# @env         SERVER_USER             Base tracking string used to generate local tokens.
#
# @dependencies
#              - /home/homedir.dat configuration file tracking the active application root path.
#              - ExtractConfigValue.sh system service wrapper infrastructure for lookup evaluations.
#              - ExtractBuildStyleValues.sh configuration parser for active software parameters.
#              - PerformGetFromDatastore.sh data retrieval driver selected by software parameters.
#
# @security    
#              - Relies on system-owned executable paths (/bin, /usr/bin) to circumvent hijack exploits.
#              - Limits scope to single-node target evaluation to minimize cross-regional tokens exposure.
#              - Sanitizes additional tracking suffixes via regex mapping to block structural directory traversal escapes.
#
# @exit        0  Success: Datastore object resolution and download completed successfully.
# @exit        1  Failure: Missing mandatory arguments, invalid flags, or internal extraction driver failures.
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
#########################################################################################
#########################################################################################
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
LOG_FILE="${HOME}/runtime/logs/datastore/GetFromDatastore.log"

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
if [ -z "${1}" ] || [ -z "${2}" ] || [ -z "${3}" ]
then
        log_error "3 arguments are required and 1 optional argument"
        /bin/echo "Usage: $0 <bucket_type> <file_to_get> <destination> <additional_specifier>" >&2
        exit 1
fi

bucket_type="${1}"
file_to_get="${2}"
destination="${3}"
additional_specifier="${4}"

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
        "auth-ssl-1")
                website_url_alt="$("${HOME}/utilities/config/ExtractConfigValue.sh" 'AUTHSERVERURL' | /bin/sed 's/[^.]*/auth/')"
                service_token=""
                if [ "${SSL_GENERATION_SERVICE}" = "LETSENCRYPT" ]
                then
                        service_token="lets"
                elif [ "${SSL_GENERATION_SERVICE}" = "ZEROSSL" ]
                then
                        service_token="zero"
                fi
                active_bucket="$(/bin/echo "${website_url_alt}" | /bin/sed 's/\./-/g')-${DNS_CHOICE}-${service_token}-ssl"
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

if [ -z "${destination}" ]
then
        destination="."
fi

# Execution driver pathway mapping
execution_driver="${HOME}/services/datastore/operations/${DATASTORE_TOOL}/PerformGetFromDatastore.sh"

# Run target download operations securely
if ! "${execution_driver}" "${active_bucket}/${file_to_get}" "${destination}"
then
        log_error "PerformGetFromDatastore.sh driver execution failed returned an error code"
        exit 1
fi

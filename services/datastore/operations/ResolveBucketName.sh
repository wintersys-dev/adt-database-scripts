#!/bin/sh
#: Name:        ResolveBucketName.sh
#: Purpose:     Resolves target S3 bucket naming topologies from a bucket classification type and optional specifier.
#: Author:      Peter Winter
#: Date:        25/11/2026
#: Version:     2.0
#:
#: Usage:       ResolveBucketName.sh <bucket_type> [additional_specifier]
#:              ResolveBucketName.sh [-h|--help]
#:
#: Parameters:
#:   $1         [Required] Target bucket classification type (e.g., ssl, config, asset, backup-web, backup-db, ad-hoc, all)
#:   $2         [Optional] Contextual tracking suffix or explicit bucket name for "ad-hoc" mode
#:
#: Environment:
#:   HOME       Root directory of the server deployment toolkit (falls back to /home/homedir.dat if unset)
#:
#: Dependencies:
#:   - ${HOME}/utilities/config/ExtractConfigValue.sh
#:   - External binaries: cat, echo, grep, cut, sed, fold, head, tr
#:
#: Exit Codes:
#:   0          Target bucket name resolved and printed to stdout
#:   1          Missing configuration, invalid arguments, or unsupported bucket type
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

# Resolve HOME from environment or fallback /home/homedir.dat
if [ -z "${HOME}" ] && [ -r /home/homedir.dat ]
then
        HOME="$(/bin/cat /home/homedir.dat)"
fi

if [ -z "${HOME}" ] || [ ! -d "${HOME}" ]
then
        /bin/echo "Error: HOME environment variable is unset or invalid." >&2
        exit 1
fi

# Validate mandatory positional parameters
if [ -z "${1}" ]
then
        /bin/echo "Error: ResolveBucketName.sh requires at least 1 argument (<bucket_type>)." >&2
        exit 1
fi

bucket_type="${1}"
additional_specifier="${2}"

# Verify config extractor helper exists
config_extractor="${HOME}/utilities/config/ExtractConfigValue.sh"
if [ ! -x "${config_extractor}" ]
then
        /bin/echo "Error: Configuration extractor script missing or not executable at ${config_extractor}" >&2
        exit 1
fi

# Retrieve core deployment context variables from node configuration
WEBSITE_URL="$("${config_extractor}" 'WEBSITEURL')"
DNS_CHOICE="$("${config_extractor}" 'DNSCHOICE')"
SSL_GENERATION_SERVICE="$("${config_extractor}" 'SSLGENERATIONSERVICE')"

if [ -z "${WEBSITE_URL}" ] && [ "${bucket_type}" != "auth" ] && [ "${bucket_type}" != "auth-ssl" ] && [ "${bucket_type}" != "auth-config" ] && [ "${bucket_type}" != "ad-hoc" ] && [ "${bucket_type}" != "all" ]
then
        /bin/echo "Error: Failed to fetch required configuration variable WEBSITEURL." >&2
        exit 1
fi

# Resolve config suffix: prefer explicit specifier if supplied, otherwise derive from SERVERUSER
config_suffix="${additional_specifier}"
if [ -z "${config_suffix}" ]
then
        SERVER_USER="$("${config_extractor}" 'SERVERUSER')"
        config_suffix="$(/bin/echo "${SERVER_USER}" | /usr/bin/fold -w 4 | /usr/bin/head -n 1 | /usr/bin/tr '[:upper:]' '[:lower:]')"
fi

# Construct the target bucket name based on bucket classification
case "${bucket_type}" in
        "ssl")
                if [ "${SSL_GENERATION_SERVICE}" = "LETSENCRYPT" ]
                then
                        service_token="lets"
                elif [ "${SSL_GENERATION_SERVICE}" = "ZEROSSL" ]
                then
                        service_token="zero"
                else
                        /bin/echo "Error: Unsupported or empty SSLGENERATIONSERVICE '${SSL_GENERATION_SERVICE}'." >&2
                        exit 1
                fi
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-${DNS_CHOICE}-${service_token}-ssl"
                ;;
        "auth-ssl")
                AUTH_SERVER_URL="$("${config_extractor}" 'AUTHSERVERURL')"
                AUTH_DNS_CHOICE="$("${config_extractor}" 'AUTHDNSCHOICE')"
                if [ "${SSL_GENERATION_SERVICE}" = "LETSENCRYPT" ]
                then
                        service_token="lets"
                elif [ "${SSL_GENERATION_SERVICE}" = "ZEROSSL" ]
                then
                        service_token="zero"
                else
                        /bin/echo "Error: Unsupported or empty SSLGENERATIONSERVICE '${SSL_GENERATION_SERVICE}'." >&2
                        exit 1
                fi
                active_bucket="$(/bin/echo "${AUTH_SERVER_URL}" | /bin/sed 's/\./-/g')-${AUTH_DNS_CHOICE}-${service_token}-ssl"
                ;;
        "multi-region")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-multi-region"
                ;;
        "config")
                active_bucket="$(/bin/echo "${WEBSITE_URL}-config" | /bin/sed 's/\./-/g')-${config_suffix}"
                ;;
        "auth-config")
                AUTH_SERVER_URL="$("${config_extractor}" 'AUTHSERVERURL')"
                active_bucket="$(/bin/echo "${AUTH_SERVER_URL}-config" | /bin/sed 's/\./-/g')-${config_suffix}"
                ;;
        "asset")
                active_bucket="$(/bin/echo "${WEBSITE_URL}-assets-${additional_specifier}" | /bin/sed -e 's/\./-/g' -e 's;/;-;g' -e 's/--/-/g')"
                ;;
        "scaling"|"backup-webroot")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-${additional_specifier}"
                ;;
        "firewall-auth-laptop-ips"|"whitelist-auth-laptop-ips"|"firewall-emailed-links"|"whitelist-emailed-links"|"basic-auth-credentials")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-${bucket_type}"
                ;;
        "wire-guard")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-wireguard"
                ;;
        "wire-guard-emails")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-wireguard-emails"
                ;;
        "wire-guard-emailed-links")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-wireguard-emailed-links"
                ;;
        "backup-db")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-db-${additional_specifier}"
                ;;
        "auth")
                active_bucket="authip-adt-allowed-${additional_specifier}"
                ;;
        "dbaas")
                active_bucket="$(/bin/echo "${WEBSITE_URL}" | /bin/sed 's/\./-/g')-${DNS_CHOICE}-dbaas"
                ;;
        "ad-hoc")
                active_bucket="${additional_specifier}"
                ;;
        "all")
                active_bucket="all"
                ;;
        *)
                /bin/echo "Error: Unknown bucket classification type '${bucket_type}'." >&2
                exit 1
                ;;
esac

if [ -z "${active_bucket}" ]
then
        /bin/echo "Error: Resolved target bucket name is empty for classification '${bucket_type}'." >&2
        exit 1
fi

/bin/echo "${active_bucket}"
exit 0

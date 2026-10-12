#!/bin/sh
####################################################################################
# Author: Peter Winter
# Date  : 10/4/2016
# Description : Set up the firewall for the database machine
####################################################################################
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
#####################################################################

export HOME="`/bin/cat /home/homedir.dat`"

BUILDOS="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDOS'`"
DB_PORT="`${HOME}/utilities/config/ExtractConfigValue.sh 'DBPORT'`"
SSH_PORT="`${HOME}/utilities/config/ExtractConfigValue.sh 'SSHPORT'`"
CLOUDHOST="`${HOME}/utilities/config/ExtractConfigValue.sh 'CLOUDHOST'`"
VPC_IP_RANGE="`${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE'`"
SERVER_USER="`${HOME}/utilities/config/ExtractConfigValue.sh 'SERVERUSER'`"
BUILD_MACHINE_IP="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDMACHINEIP'`"

if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "FAIL2BAN" | /usr/bin/awk -F':' '{print $NF}'`" = "active" ] )
then
        if ( [ ! -f /etc/fail2ban/jail.d/jail.local ] )
        then
                if ( [ ! -d /etc/fail2ban/jail.d ] )
                then
                        /bin/mkdir -p /etc/fail2ban/jail.d
                fi
        fi

        if ( [ -d /etc/fail2ban/jail.d ] && ( [ ! -f /etc/fail2ban/jail.d/jail.local ] || [ "`/bin/grep '#ADTFAIL2BAN' /etc/fail2ban/jail.d/jail.local`" = "" ] ) )
        then
                /bin/cp ${HOME}/services/security/config/fail2ban.conf /etc/fail2ban/jail.d/jail.local
                /bin/sed -i "s/XXXXSSHPORTXXXX/${SSH_PORT}/g" /etc/fail2ban/jail.d/jail.local
                /bin/sed -i "s;#XXXXVPCIPRANGEXXXX;${VPC_IP_RANGE};g" /etc/fail2ban/jail.d/jail.local
                /bin/sed -i "s;#XXXXBUILDMACHINEIPXXXX;${BUILD_MACHINE_IP}/32;g" /etc/fail2ban/jail.d/jail.local
                ${HOME}/utilities/processing/RunServiceCommand.sh fail2ban restart
        fi
fi

if ( [ -f ${HOME}/runtime/firewall.dat ] && [ "`/usr/bin/find ${HOME}/runtime/firewall.dat -mmin -1 -print`" != "" ] )
then
        /bin/rm ${HOME}/runtime/FIREWALL-ACTIVE
fi

if ( [ -f ${HOME}/runtime/FIREWALL-ACTIVE ] )
then
        exit
fi

allow_vpc="sshd : `/bin/echo "${VPC_IP_RANGE}" | /usr/bin/awk -F'.' '{print $1,$2,$3.}' | /bin/sed 's/ /./g'`."
/bin/echo "${allow_vpc}" >> /etc/hosts.allow
/bin/echo "sshd : ${BUILD_MACHINE_IP}" >> /etc/hosts.allow

/bin/echo "ALL : ALL" >> /etc/hosts.deny

#This stream redirection is required for correct function, please do not remove
#exec >${HOME}/logs/firewall/FIREWALL_CONFIGURATION.log
#exec 2>&1

if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:1`" = "0" ] && [ "`${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:3`" = "0" ] )
then
        exit
fi


initialised="0"
if ( [ ! -f ${HOME}/runtime/FIREWALL-INITIALISED ] )
then

		
                /usr/bin/yes | /usr/sbin/ufw reset
                /usr/sbin/ufw delete allow 22/tcp
                /usr/sbin/ufw logging off
                /usr/sbin/ufw reload
                initialised="1"
                /bin/touch ${HOME}/runtime/FIREWALL-INITIALISED 
fi

${HOME}/services/security/firewall/KnickersUp.sh

if ( [ -f ${HOME}/runtime/FIREWALL-ACTIVE ] )
then
        /usr/sbin/ufw reset
fi

updated_ssh="0"
if ( [ "`/bin/grep ${VPC_IP_RANGE} /etc/ssh/sshd_config`" = "" ] )
then
        if ( [ "${SERVER_USER}" != "" ] && [ "${VPC_IP_RANGE}" != "" ] )
        then
                if ( [ "`/bin/grep "AllowUsers" /etc/ssh/sshd_config.d/99-hardening.conf | /bin/grep "${SERVER_USER}" | /bin/grep "${VPC_IP_RANGE}"`" = "" ] )
                then
                        /bin/echo "AllowUsers ${SERVER_USER}@${VPC_IP_RANGE}" >> /etc/ssh/sshd_config.d/99-hardening.conf
                        updated_ssh="1"
                fi
        fi
fi

if ( [ "`/bin/grep ${BUILD_MACHINE_IP} /etc/ssh/sshd_config`" = "" ] )
then
        if ( [ "${SERVER_USER}" != "" ] && [ "${BUILD_MACHINE_IP}" != "" ] )
        then
                if ( [ "`/bin/grep "AllowUsers" /etc/ssh/sshd_config.d/99-hardening.conf | /bin/grep "${SERVER_USER}" | /bin/grep "${BUILD_MACHINE_IP}"`" = "" ] )
                then
                        /bin/echo "AllowUsers ${SERVER_USER}@${BUILD_MACHINE_IP}" >> /etc/ssh/sshd_config.d/99-hardening.conf
                        updated_ssh="1"
                fi
        fi
fi

if ( [ "${updated_ssh}" = "1" ] )
then
        ${HOME}/utilities/processing/RunServiceCommand.sh "ssh" restart
fi

updated="0"


if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh BUILDMACHINEVPC:0`" = "1" ] )
then
	if ( [ "`/usr/sbin/ufw status | /bin/grep "${SSH_PORT}.*ALLOW.*${BUILD_MACHINE_IP}"`" = "" ] )
	then
		/usr/sbin/ufw allow from ${BUILD_MACHINE_IP}/32 to any port ${SSH_PORT}
		/bin/sleep 2
		updated="1"
	fi
fi



        if ( [ "`/usr/sbin/ufw status | /bin/grep "${SSH_PORT}.*ALLOW.*${VPC_IP_RANGE}"`" = "" ] )
        then
                /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port ${SSH_PORT}
                if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEINSTALLATIONTYPE:DBaaS`" = "0" ] )
                then
                        /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port ${DB_PORT}
                fi
                /bin/sleep 5
                updated="1"
        fi


if ( [ -f ${HOME}/runtime/firewall.dat ] )
then
        ports="`/bin/grep "^DATABASEPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/DATABASEPORTS://g'`"

        for port_token in ${ports}
        do
                delete="no"
                if ( [ "`/bin/echo ${port_token} | /bin/grep 'ipv4'`" != "" ] )
                then
                        port="`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $1}'`"
                        ip_address="`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $4}'`"
                        if ( [ "`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $6}'`" = "DELETE" ] )
                        then
                                delete="yes"
                        fi
                fi

                        if ( [ "`/usr/sbin/ufw status | /bin/grep "${port}.*ALLOW.*${ip_address}"`" = "" ] && [ "${delete}" != "yes" ] )
                        then
                                /usr/sbin/ufw allow from ${ip_address} to any port ${port}
                                updated="1"
                        else
                                if ( [ "`/usr/sbin/ufw status | /bin/grep "${port}.*ALLOW"`" != "" ] && [ "${delete}" = "yes" ] )
                                then
                                        /usr/bin/yes | /usr/sbin/ufw delete `/usr/sbin/ufw status numbered | /bin/grep ${port} | /usr/bin/awk -F"[\[\]]" '{print $2}' | /bin/sed 's/ //g'`
                                        updated="1"
                                fi

                        fi
             
        done
fi

if ( [ "${updated}" = "1" ] || [ "${initialised}" = "1" ] )
then
                /usr/sbin/ufw -f enable
                /usr/sbin/ufw reload

        if ( [ "${BUILDOS}" = "ubuntu" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh systemd-networkd.service restart
        elif ( [ "${BUILDOS}" = "debian" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh networking restart
        fi
fi


        if ( [ "`/usr/bin/ufw status | /bin/grep 'inactive'`" = "" ] )
        then
                /bin/touch ${HOME}/runtime/FIREWALL-ACTIVE
        fi


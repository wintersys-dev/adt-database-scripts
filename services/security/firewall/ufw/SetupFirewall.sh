#!/bin/sh
#####################################################################################
# Author: Peter Winter
# Date :  9/4/2016
# Description: Setup the firewall
#####################################################################################
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
##################################################################################
##################################################################################
#set -x 

export HOME="`/bin/cat /home/homedir.dat`"

if ( [ ! -d ${HOME}/logs/firewall ] )
then
        /bin/mkdir -p ${HOME}/logs/firewall
fi

out_file="firewall/firewall-out-`/bin/date | /bin/sed 's/ //g'`"
exec 1>>${HOME}/logs/${out_file}
err_file="firewall/firewall-err-`/bin/date | /bin/sed 's/ //g'`"
exec 2>>${HOME}/logs/${err_file}

BUILD_MACHINE_IP="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDMACHINEIP'`"
SERVER_USER="`${HOME}/utilities/config/ExtractConfigValue.sh 'SERVERUSER'`"
SSH_PORT="`${HOME}/utilities/config/ExtractConfigValue.sh 'SSHPORT'`"
CLOUDHOST="`${HOME}/utilities/config/ExtractConfigValue.sh 'CLOUDHOST'`"
DNS_CHOICE="`${HOME}/utilities/config/ExtractConfigValue.sh 'DNSCHOICE'`"
VPC_IP_RANGE="`${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE'`"
BUILDOS="`${HOME}/utilities/config/ExtractConfigValue.sh 'BUILDOS'`"
NO_REVERSE_PROXIES="`${HOME}/utilities/config/ExtractConfigValue.sh 'NOREVERSEPROXIES'`"
AUTHENTICATOR_TYPE="`${HOME}/utilities/config/ExtractConfigValue.sh 'AUTHENTICATORTYPE'`"


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

#exec >${HOME}/logs/firewall/FIREWALL_CONFIGURATION.log
#exec 2>&1
##################################################################################

if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:1`" = "0" ] && [ "`${HOME}/utilities/config/CheckConfigValue.sh ACTIVEFIREWALLS:3`" = "0" ] )
then
        exit
fi


		openness=""
		if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $3}'`" = "limit" ] )
		then
			openness="limit"
		else
			openness="allow"
		fi
		if ( [ "`/usr/bin/hostname | /bin/grep '^ws-'`" != "" ] && [ "${NO_REVERSE_PROXIES}" != "0" ] )
		then
			openness="allow"
		fi

if ( [ ! -f ${HOME}/runtime/FIREWALL-ACTIVE ] )
then
        if ( [ -f ${HOME}/runtime/authenticator/ipaddresses.dat ] )
        then
                /bin/rm ${HOME}/runtime/authenticator/ipaddresses.dat
        fi
fi

initialised="0"

if ( [ ! -f ${HOME}/runtime/FIREWALL-INITIALISED ] )
then
        if ( [ ! -f ${HOME}/runtime/FIREWALL-ACTIVE ] )
        then
                /usr/bin/yes | /usr/sbin/ufw reset
                /usr/sbin/ufw delete allow 22/tcp
                /usr/sbin/ufw logging off
                VPC_IP_RANGE="`${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE'`"
                ip_addresses="`/usr/sbin/ufw status | /bin/grep "^443" | /bin/grep -v "${VPC_IP_RANGE}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"`"

                for ip_address in ${ip_addresses}
                do
                        /usr/sbin/ufw delete allow from ${ip_address}
                done

                /usr/sbin/ufw reload
				intialised="1"
                /bin/touch ${HOME}/runtime/FIREWALL-INITIALISED 
        fi
fi

#Make absoultely certain that we are tied down
${HOME}/services/security/firewall/KnickersUp.sh

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

#Because authenticator machines are more public facing that the other machines in our architecture we want to block ssh requests 
#to our infrastructure that originate from authenticator machines as they are slightly more vulnerable than our core infratructure machines.

if ( [ "`/usr/bin/hostname | /bin/grep '\-auth\-'`" = "" ] )
then
	authenticator_ip="`${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "authenticatorip/*" | /usr/bin/tr '\n' ' '`"
	authenticator_public_ip="`${HOME}/services/datastore/config/wrapper/ListFromDatastore.sh "config" "authenticatorpublicip/*" | /usr/bin/tr '\n' ' '`"

	if ( [ "${authenticator_ip}" != "" ] )
	then

			/usr/sbin/ufw deny from ${authenticator_ip}
	fi

	if ( [ "${authenticator_public_ip}" != "" ] )
	then

			/usr/sbin/ufw deny from ${authenticator_public_ip}
	fi
fi

if ( [ "`/usr/bin/hostname | /bin/grep '^rp\-'`" = "" ] && [ "${AUTHENTICATOR_TYPE}" = "wire-guard" ] )
then
        wireguard_port="`/usr/bin/expr ${SSH_PORT} + 1`"

                if ( [ "`/usr/sbin/ufw status | /bin/grep  "${wireguard_port}.*ALLOW.*"`" = "" ] )
                then
                        /usr/sbin/ufw allow ${wireguard_port}
                        /bin/sleep 2
                        updated="1"
                fi
fi

if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh BUILDMACHINEVPC:0`" = "1" ] )
then
	    if ( [ "`/usr/sbin/ufw status | /bin/grep  "${SSH_PORT}.*ALLOW.*${BUILD_MACHINE_IP}"`" = "" ] )
		then
			/usr/sbin/ufw allow from ${BUILD_MACHINE_IP}/32 to any port ${SSH_PORT}
			/usr/sbin/ufw allow from ${BUILD_MACHINE_IP}/32 to any port 443
			/bin/sleep 2
			updated="1"
		fi
fi


        if ( [ "`/usr/sbin/ufw status | /bin/grep "${SSH_PORT}.*ALLOW.*${VPC_IP_RANGE}"`" = "" ] )
        then
                /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port ${SSH_PORT}
                /usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port 443
				/usr/sbin/ufw allow from ${VPC_IP_RANGE} to any port 80
                updated="1"
        fi

if ( [ -f ${HOME}/runtime/firewall.dat ] )
then
	if ( [ "`/usr/bin/hostname | /bin/grep '\-rp-'`" != "" ] )
	then
		ports="`/bin/grep "^REVERSEPROXYPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/REVERSEPROXYPORTS://g'`"
	elif ( [ "`/usr/bin/hostname | /bin/grep '^ws-'`" != "" ] )
	then
		ports="`/bin/grep "^WEBSERVERPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/WEBSERVERPORTS://g'`"
	elif ( [ "`/usr/bin/hostname | /bin/grep '\-auth-'`" != "" ] )
	then
		ports="`/bin/grep "^AUTHENTICATORPORTS" ${HOME}/runtime/firewall.dat | /bin/sed 's/AUTHENTICATORPORTS://g'`"
	fi

	for port_token in ${ports}
	do
		delete="no"
        if ( [ "`/bin/echo ${port_token} | /bin/grep 'ipv4'`" != "" ] )
        then
        	port="`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $1}'`"
        	ip_address="`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $4}'`"
                        
			if ( [ "`/bin/echo ${port_token} | /usr/bin/awk -F'|' '{print $4}'`" = "DELETE" ] )
        	then
        		delete="yes"
    		fi
    	fi

        	if ( [ "${ip_address}" = "cloudflare" ] )
        	then
        		for ip in `/usr/bin/curl https://www.cloudflare.com/ips-v4/#`
            	do
            		if ( [ "`/usr/sbin/ufw status | /bin/grep "ALLOW.*${ip}"`" = "" ] )
            		then
            			/usr/sbin/ufw ${openness} from ${ip} to any port 443
        				updated="1"
        			fi
        		done
    		elif ( [ "`/usr/sbin/ufw status | /bin/grep "${port}" | /bin/grep "ALLOW" | /bin/grep "${ip_address}"`" = "" ] && [ "${delete}" != "yes" ] )
    		then
            	/usr/sbin/ufw ${openness} from ${ip_address} to any port ${port}
            	updated="1"
            else
            	if ( [ "`/usr/sbin/ufw status | /bin/grep "${port}" | /bin/grep "ALLOW" | /bin/grep "${ip_address}"`" != "" ] && [ "${delete}" = "yes" ] )
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

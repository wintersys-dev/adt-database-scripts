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

firewall=""
if ( [ "`${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $2}'`" = "iptables" ] )
then
        firewall="iptables"
		limit=""
		limit="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $3}'`"
		limit_burst=""
		limit_burst="`${HOME}/utilities/config/ExtractBuildStyleValues.sh "FIREWALL" | /usr/bin/awk -F':' '{print $4}'`"
		if ( [ "${limit}" = "" ] || [ "${limit_burst}" = "" ] )
		then
			limited="off"
		else
			if ( [ "${limit}" -eq "${limit}" 2>/dev/null ] && [ "${limit_burst}" -eq "${limit_burst}" 2>/dev/null ] )
        	then
				limited="on"
			else
				limited="off"
			fi
		fi
		if ( [ "`/usr/bin/hostname | /bin/grep '^ws-'`" != "" ] && [ "${NO_REVERSE_PROXIES}" != "0" ] )
		then
			limited="off"
		fi
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
	if ( [ "${firewall}" = "iptables" ] && [ ! -f ${HOME}/runtime/FIREWALL-INITIALISED ] )
        then
                /usr/sbin/iptables -P INPUT DROP
                /usr/sbin/iptables -P FORWARD DROP
                /usr/sbin/iptables -P OUTPUT ACCEPT
                /usr/sbin/iptables -A INPUT -i lo -j ACCEPT
                /usr/sbin/iptables -A OUTPUT -o lo -j ACCEPT

                /usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
                /usr/sbin/iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT
                /usr/sbin/iptables -A INPUT -m conntrack --ctstate INVALID -j DROP

                /usr/sbin/ip6tables -P INPUT DROP
                /usr/sbin/ip6tables -P FORWARD DROP
                /usr/sbin/ip6tables -P OUTPUT ACCEPT
                /usr/sbin/ip6tables -A INPUT -i lo -j ACCEPT
                /usr/sbin/ip6tables -A OUTPUT -o lo -j ACCEPT

                VPC_IP_RANGE="`${HOME}/utilities/config/ExtractConfigValue.sh 'VPCIPRANGE'`"
                ip_addresses="`/usr/sbin/iptables -L INPUT -n | /bin/grep "443$" | /bin/grep -v "${VPC_IP_RANGE}" | /bin/grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"`"
                for ip_address in ${ip_addresses}
                do
                        /usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp --dport 443 -j ACCEPT
                done
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
		if ( [ "${firewall}" = "iptables" ] )
		then
			/usr/sbin/iptables -I INPUT -s ${authenticator_ip} -j DROP
		fi
	fi

	if ( [ "${authenticator_public_ip}" != "" ] )
	then
		if ( [ "${firewall}" = "iptables" ] )
		then
			/usr/sbin/iptables -I INPUT -s ${authenticator_public_ip} -j DROP
		fi
	fi
fi

if ( [ "`/usr/bin/hostname | /bin/grep '^rp\-'`" = "" ] && [ "${AUTHENTICATOR_TYPE}" = "wire-guard" ] )
then
        wireguard_port="`/usr/bin/expr ${SSH_PORT} + 1`"
		if ( [ "${firewall}" = "iptables" ] )
        then
                if ( [ "`/usr/sbin/iptables --list-rules | /bin/grep ".*${wireguard_port}.*ACCEPT"`" = "" ] )
                then
                        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport ${wireguard_port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport ${wireguard_port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p udp --dport ${wireguard_port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p udp --sport ${wireguard_port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        updated="1"
                fi
        fi
fi

if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh BUILDMACHINEVPC:0`" = "1" ] )
then
	if ( [ "${firewall}" = "iptables" ] )
	then
		if ( [ "`/usr/sbin/iptables --list-rules | /bin/grep "${BUILD_MACHINE_IP}.*${SSH_PORT}.*ACCEPT"`" = "" ] )
		then
                        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport ${SSH_PORT} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport ${SSH_PORT} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A OUTPUT -s ${BUILD_MACHINE_IP}/32 -p tcp --sport 443 -m conntrack --ctstate ESTABLISHED -j ACCEPT
                        /usr/sbin/iptables -A INPUT -s ${BUILD_MACHINE_IP}/32 -p ICMP --icmp-type 8 -j ACCEPT
			updated="1"
		fi
	fi
fi


if ( [ "${firewall}" = "iptables" ] )
then
        if ( [ "`/usr/sbin/iptables --list-rules | /bin/grep "${VPC_IP_RANGE}.*${SSH_PORT}.*ACCEPT"`" = "" ] )
        then
                /usr/sbin/iptables -A INPUT -s ${VPC_IP_RANGE} -p tcp --dport ${SSH_PORT} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A INPUT -s ${VPC_IP_RANGE} -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A INPUT -s ${VPC_IP_RANGE} -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                /usr/sbin/iptables -A INPUT -s ${VPC_IP_RANGE} -p ICMP --icmp-type 8 -j ACCEPT
                updated="1"
        fi

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

		if ( [ "${firewall}" = "iptables" ] )
        then
            if ( [ "${ip_address}" = "cloudflare" ] )
            then
            	for ip in `/usr/bin/curl https://www.cloudflare.com/ips-v4/#`
            	do
            		if ( [ "`/usr/sbin/iptables --list-rules | /bin/grep "${ip}.*443.*ACCEPT"`" = "" ] )
            		then
						/usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
						if ( [ "${limited}" = "on" ] )
						then
							/usr/sbin/iptables -A INPUT -s ${ip} -p tcp --dport ${port} -m conntrack --ctstate NEW -m limit --limit 20/min --limit-burst 30 -j ACCEPT
							/usr/sbin/iptables -A INPUT -s ${ip} -p tcp --dport ${port} -m conntrack --ctstate NEW -j DROP
							/usr/sbin/iptables -A OUTPUT -s ${ip} -p tcp --sport ${port} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
                		elif ( [ "${limited}" = "off" ] )
						then
							/usr/sbin/iptables -I INPUT -s ${ip} -p tcp -m tcp --dport 443 -j ACCEPT
						fi
						updated="1"
                    fi
                done
            elif ( [ "`/usr/sbin/iptables --list-rules | /bin/grep "${ip_address}.${port}.*ACCEPT"`" = "" ] && [ "${delete}" != "yes" ] )
            then
				if ( [ "${limited}" = "on" ] )
				then
					/usr/sbin/iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
					/usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW -m limit --limit ${limit}/min --limit-burst ${limit_burst} -j ACCEPT
					/usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW -j DROP
					/usr/sbin/iptables -A OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
				elif ( [ "${limited}" = "off" ] )
				then
                	/usr/sbin/iptables -A INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                	/usr/sbin/iptables -A OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                fi    
				updated="1"
            else
            	if ( [ "`/usr/sbin/iptables --list-rules | /bin/grep "${ip_address}.${port}.*ACCEPT"`" != "" ] && [ "${delete}" = "yes" ] )
            	then
            		if ( [ "${limited}" = "on" ] )
					then
						/usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp --dport ${port} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
                		/usr/sbin/iptables -D OUTPUT -s ${ip_address} -p tcp --sport ${port} -m conntrack --ctstate ESTABLISHED -j ACCEPT
                    elif ( [ "${limited}" = "off" ] )
					then      
						/usr/sbin/iptables -D INPUT -s ${ip_address} -p tcp -m tcp --dport ${port} -j ACCEPT
					fi
					updated="1"
            	fi
			fi
		fi
	done
fi

if ( [ "${updated}" = "1" ] || [ "${initialised}" = "1" ] )
then
	if ( [ "${firewall}" = "iptables" ] )
        then
                /usr/sbin/iptables-save > /etc/iptables/rules.v4
                /usr/sbin/ip6tables-save > /etc/iptables/rules.v6
        fi

        if ( [ "${BUILDOS}" = "ubuntu" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh systemd-networkd.service restart
        elif ( [ "${BUILDOS}" = "debian" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh networking restart
        fi
fi

if ( [ "${firewall}" = "iptables" ] )
then
        if ( [ "`${HOME}/utilities/processing/RunServiceCommand.sh netfilter-persistent status | /bin/grep Loaded | /bin/grep enabled`" != "" ] )
        then
                if ( [ "`${HOME}/utilities/processing/RunServiceCommand.sh netfilter-persistent status | /bin/grep active`" != "" ] )
                then
                        /bin/touch ${HOME}/runtime/FIREWALL-ACTIVE
                fi
        fi
fi

#!/bin/sh
#################################################################################
# Author: Peter Winter
# Date :  9/4/2016
# Description: Runs a check to see if the database is up and running
#################################################################################
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

if ( [ ! -f ${HOME}/runtime/DATABASE_READY ] )
then
        exit
fi

running="0"
${HOME}/utilities/remote/ConnectToMySQLDB.sh "exit"
if ( [ "$?" = "0" ] )
then
        running="1"
else
        ${HOME}/utilities/remote/ConnectToPostgresDB.sh "\q"
        if ( [ "$?" = "0" ] )
        then
                running="1"
        else
                running="0"
        fi
fi

if ( [ "${running}" = "0" ] )
then
        if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEINSTALLATIONTYPE:Maria`" = "1" ] || [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEDBaaSINSTALLATIONTYPE:Maria`" = "1" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh mariadb restart

                if ( [ "$?" != "0" ] )
                then
                        /bin/touch ${HOME}/runtime/DATABASE_NOT_RUNNING
                        /bin/echo "${0} `/bin/date`: Couldn't restart the mariadb database this is a problem that needs to be looked into" 
                        ${HOME}/services/email/SendEmail.sh "DATABASE MIGHT NOT BE RUNNING" "I think that your database might not be running" "ERROR"
                else
                        /bin/rm ${HOME}/runtime/DATABASE_NOT_RUNNING
                fi
        fi

        if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEINSTALLATIONTYPE:MySQL`" = "1" ] || [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEDBaaSINSTALLATIONTYPE:MySQL`" = "1" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh mysql restart

                if ( [ "$?" != "0" ] )
                then
                        /bin/touch ${HOME}/runtime/DATABASE_NOT_RUNNING
                        /bin/echo "${0} `/bin/date`: Couldn't restart the mariadb database this is a problem that needs to be looked into" 
                        ${HOME}/services/email/SendEmail.sh "DATABASE MIGHT NOT BE RUNNING" "I think that your database might not be running" "ERROR"
                else
                        /bin/rm ${HOME}/runtime/DATABASE_NOT_RUNNING
                fi
        fi
        if ( [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEINSTALLATIONTYPE:Postgres`" = "1" ] || [ "`${HOME}/utilities/config/CheckConfigValue.sh DATABASEDBaaSINSTALLATIONTYPE:Postgres`" = "1" ] )
        then
                ${HOME}/utilities/processing/RunServiceCommand.sh postgresql restart

                if ( [ "$?" != "0" ] )
                then
                        /bin/touch ${HOME}/runtime/DATABASE_NOT_RUNNING
                        /bin/echo "${0} `/bin/date`: Couldn't restart the mariadb database this is a problem that needs to be looked into" 
                        ${HOME}/services/email/SendEmail.sh "DATABASE MIGHT NOT BE RUNNING" "I think that your database might not be running" "ERROR"
                else
                        /bin/rm ${HOME}/runtime/DATABASE_NOT_RUNNING
                fi
        fi
else
        if ( [ -f ${HOME}/runtime/DATABASE_NOT_RUNNING ] )
        then
                ${HOME}/services/email/SendEmail.sh "DATABASE BACK UP AND RUNNING" "I think that your database is back up and running" "ERROR"
                /bin/rm ${HOME}/runtime/DATABASE_NOT_RUNNING
        fi
fi


#set -x

current_day="`/usr/bin/date +%d`"
current_month="`/usr/bin/date +%m | /bin/sed 's/^0//g'`"
current_year="`/usr/bin/date +%y`"
archive_day="`/usr/bin/expr ${current_day} - 1`"
archive_date="archive-${archive_day}-${current_month}-${current_year}"

if ( [ ! -d ${HOME}/logs/archives/${archive_date} ] )
then
        /bin/mkdir -p ${HOME}/logs/archives/${archive_date}
fi

cd ${HOME}/logs
/bin/tar cvfz ${HOME}/logs/archives/${archive_date}/archive.tar.gz --exclude "./archives" .

if ( [ ! -d ${HOME}/runtime/logging_archive_workarea ] )
then
        /bin/mkdir -p ${HOME}/runtime/logging_archive_workarea
fi

if ( [ "$?" = "0" ] )
then
        /bin/mv ${HOME}/logs/archives ${HOME}/runtime/logging_archive_workarea
        /bin/rm -r ${HOME}/logs/*
        /bin/mv ${HOME}/runtime/logging_archive_workarea/archives ${HOME}/logs/
fi

#!/bin/bash -x
# ###########################################################################
#       Name:           MySQL_auto_deployment.sh
#       Location:       
#       Function:       Deploy MySQL automatically 
#       Author:         Cheng Ran 
#       Create Date:    2018/01/16
#		Modify Date:	2018/03/08
#############################################################################
#check if executor is root 
USER_ID=`id | awk -F '(' '{print $1}' | awk -F '=' '{print $2}'`
if [ $USER_ID != 0 ]; then
echo 'Script is interrupted because the executor is not root user!'
exit 1
fi

#check if disk space under /data/01 is enough 
DISK_USE=`df -h | grep /data/01 | head -n 1 | awk -F ' ' '{print $5}' | awk -F '%' '{print $1}'`
if [ $DISK_USE -ge 90 ]; then 
echo 'The disk space under /data/01 is not enough!'
exit 1
fi

#check if MySQL is already running
PID1=`ps -ef|grep mysqld | grep -v grep | sed -n "1p" | awk -F ' ' '{print $2}'`
if [ -z $PID1 ]; then
	STARTTIME=`date "+%F %H:%M:%S"`
	echo "Staring depoly MySQL at $STARTTIME"
else
	echo 'MySQL is already running on this server!'
	exit 1
fi

#check instance environment is DEV/STAGE or PROD
NAME_FLAG=`hostname -f | awk -F '-' '{print $1}'`
LENGTH=`echo $NAME_FLAG | wc -L`
if [ $LENGTH == 4 ]; then
ENV='DEV'
fi
if [ $LENGTH == 3 ]; then
ENV='PROD'
fi 

#download from httpd @ ec2t-dbaadmin-01 or ec2-dbaadmin-03
cd /usr/local/
if [ $ENV == 'DEV' ]; then
wget http://yourIP/MySQL/mysql-5.6.23-linux-glibc2.5-x86_64.tar.gz
	if [ $? -ne 0 ];then
		echo 'An error occured when downloading MySQL installation file, please check!'
		exit 1
	fi
fi
if [ $ENV == 'PROD' ]; then
wget http://yourIP/MySQL/mysql-5.6.23-linux-glibc2.5-x86_64.tar.gz
	if [ $? -ne 0 ];then
		echo 'An error occured when downloading MySQL installation file, please check!'
		exit 1
	fi
fi

#Create user and directory, then decompress tar pakage
export GID=`expr substr "$(id mysqladmin | awk -F '=' '{print $3}')" 1 3`
if [ $GID == 101 ]; then
	tar -xvzf mysql-5.6.23-linux-glibc2.5-x86_64.tar.gz
	mv mysql-5.6.23-linux-glibc2.5-x86_64 mysql
	chown mysqladmin:dba /usr/local/mysql
fi

if [ $GID != 101 ]; then
	tar -xvzf mysql-5.6.23-linux-glibc2.5-x86_64.tar.gz
	mv mysql-5.6.23-linux-glibc2.5-x86_64 mysql
	groupadd -g 101 dba
	useradd -u 514 -g dba -G root -d /usr/local/mysql mysqladmin
fi

#copy files under /etc/skel for user mysqladmin 
cp /etc/skel/.* /usr/local/mysql

#create my.cnf under /etc/
cd /etc/
rm -rf /etc/my.cnf*
if [ $ENV == 'DEV' ]; then
wget http://yourIP/MySQL/my.cnf
	if [ $? -ne 0 ];then
		echo 'An error occured when downloading MySQL cnf file, please check!'
		exit 1
	fi
fi
if [ $ENV == 'PROD' ]; then
wget http://yourIP/MySQL/my.cnf
	if [ $? -ne 0 ];then
		echo 'An error occured when downloading MySQL cnf file, please check!'
		exit 1
	fi
fi

chmod 640 /etc/my.cnf
chown mysqladmin:dba /etc/my.cnf

#create directory arch and backup, then install mysql
chown mysqladmin:dba /usr/local/mysql/*
su - mysqladmin -c "cd /usr/local/mysql;mkdir arch backup"
su - mysqladmin -c "cd /usr/local/mysql/scripts;./mysql_install_db  --user=mysqladmin --basedir=/usr/local/mysql --datadir=/usr/local/mysql/data"
if [ $? -ne 0 ];then
		echo 'An error occured when installing MySQL, please check!'
		exit 1
fi

#configure mysql auto reboot
cd /usr/local/mysql
cp support-files/mysql.server /etc/rc.d/init.d/mysql
chmod +x /etc/rc.d/init.d/mysql
chkconfig --del mysql
chkconfig --add mysql
chkconfig --level 345 mysql on
echo "su - mysqladmin -c \"/etc/init.d/mysql start --federated\"" >> /etc/rc.local

#start mysql service and check 
su - mysqladmin -c "cd /usr/local/mysql/bin;./mysqld_safe &"
sleep 60
echo -e "\n"
echo -e "\n"
PID2=`ps -ef|grep mysqld | grep -v grep | sed -n "1p" | awk -F ' ' '{print $2}'`
if [ -z $PID2 ];then 
	echo "Starting MySQL service failed, please check!"
	exit 1
else 
	STATUS=`service mysql status | awk -F '[' '{print $1}' | awk -F ' ' '{print $3}'`
	if [ $STATUS == 'running' ];then
		echo "MySQL service is started"
		#configure user profile
		if [ $ENV == 'DEV' ]; then
			cd /usr/local/mysql
			wget http://yourIP/MySQL/bash_profile
			mv bash_profile .bash_profile
			chown mysqladmin:dba .bash_profile
		fi
		if [ $ENV == 'PROD' ]; then
			cd /usr/local/mysql
			wget http://yourIP/MySQL/bash_profile
			mv bash_profile .bash_profile
			chown mysqladmin:dba .bash_profile
		fi
	fi
	if [ $STATUS != 'running' ];then
		echo "Starting MySQL service failed, please check!"
		exit 1
	fi
fi

ENDTIME=`date "+%F %H:%M:%S"`
echo "Complete MySQL installation at $ENDTIME"

exit 0 

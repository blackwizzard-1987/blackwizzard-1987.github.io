---
layout:     post
title:      Cassandra One-click Installation by Fabric
subtitle:  	Cassandra single node auto installation through Fabric 
date:       2018-06-08
author:     RC
header-img: 
catalog: true
tags:
    - DBA
    - Auto Deployment
    - Fabric
---

**Note:**

**1.Cassandra 2.0 and later require Java 7u25 or later (java_version>=1.8)**

**2.The check_env function is based on AWS instance which name begin with ecx/ecxt**

**3.If you want to run this python file on fabric command line, make sure you have installed fabric(pip install fabric==1.14.0) on the target instance and added host/account name in the fabfile.py like:**

env.hosts = ['youraccountname@targetserverIP']

env.password = 'youraccountpassword'

then run **fab main** on commandline

For Fabric basic user guide, you can refer to [Google](http://www.bjhee.com/fabric.html) 

**Python file:**
```
from fabric.api import *
```
```
sudoer = 'mysqladmin'
```
```
cassandra_package = "apache-cassandra-2.1.9-bin.tar.gz"
cassandra_version = "apache-cassandra-2.1.9"
cassandra_name = "cassandra"
```
```
def check_env():
	with settings(sudo_user=sudoer):
		hostname_flag_1 = sudo("hostname -f | awk -F '-' '{print $1}' | wc -L").find('4')
		hostname_flag_2 = sudo("hostname -f | awk -F '-' '{print $1}' | wc -L").find('3')
                hostname_flag = sudo("hostname -f | awk -F '-' '{print $1}' | wc -L")
		if hostname_flag_1 > 0 or hostname_flag == '4':
			download_url = "ftp://yourdevadminIP/Cassandra/apache-cassandra-2.1.9-bin.tar.gz"
		elif hostname_flag_2 > 0 or hostname_flag == '4':
			download_url = "ftp://yourprodadminIP/Cassandra/apache-cassandra-2.1.9-bin.tar.gz"
		else:
			print "Error! The instance's env is unknown!"
		return download_url
```
```
def main():
	with settings(sudo_user=sudoer):
		with cd('/usr/local'):
			sudo("sudo su -c'wget " + check_env() + "'")
			sudo("sudo su -c'tar -xvzf " + cassandra_package + "'")
			sudo("sudo su -c'mv " + cassandra_version + " " + cassandra_name + "'")
			with cd('/usr/local/cassandra'):
				sudo("sudo su -c'mkdir commitlog'")
				sudo("sudo su -c'mkdir data'")
				with cd('/usr/local/cassandra/conf'):
					#host_ip = sudo("hostname -i")
					host_ip = env.host
					sudo("sudo su -c'chown mysqladmin:dba /usr/local/cassandra/ -R'")
					sudo('sed -i \'s/seeds: "127.0.0.1"/seeds: "' + host_ip + '"/g\' /usr/local/cassandra/conf/cassandra.yaml')
					sudo('sed -i \'s/listen_address: localhost/listen_address: "' + host_ip + '"/g\' /usr/local/cassandra/conf/cassandra.yaml')
					sudo('sed -i \'s/rpc_address: localhost/rpc_address: "'+ host_ip + '"/g\' /usr/local/cassandra/conf/cassandra.yaml')
					sudo('sed -i \'s/# num_tokens: 256/num_tokens: 256/g\' /usr/local/cassandra/conf/cassandra.yaml')
					sudo('sed -i \'19,34d\' /usr/local/cassandra/conf/cassandra-topology.properties')
					sudo('sed -i \'s/192.168.1.100/' + host_ip + '/g\' /usr/local/cassandra/conf/cassandra-topology.properties')
					sudo('sed -i \'s/default=DC1:r1/default=DC1:RAC1/g\' /usr/local/cassandra/conf/cassandra-topology.properties')
					sudo("sudo su -c'chown tnuser:appuser /usr/local/cassandra/ -R'")
					with cd('/usr/local/cassandra/bin'):
						with settings(sudo_user='tnuser'):
							sudo('nohup ./cassandra')
```							

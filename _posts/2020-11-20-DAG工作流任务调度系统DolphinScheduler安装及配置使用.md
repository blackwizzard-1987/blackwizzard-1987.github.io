---
layout:     post
title:      DAG工作流任务调度系统DolphinScheduler安装及配置使用
subtitle:  	
date:       2020-11-20
author:     RC
header-img: 
catalog: true
tags:
    - DolphinScheduler
    - spark
    - 任务调度
---

## 1.DolphinScheduler简介

Apache DolphinScheduler（incubating)(简称 DS) 是一个Apache孵化器项目，是由国内企业易观开源的大数据项目，是一个面向大数据应用的分布式工作流任务调度系统，之前叫EasyScheduler。目前DS 在国内已经有一定规模的用户基础，包括美团、平安、雪球等。与其他开源任务调度系统的比较：

![1](https://i.postimg.cc/SQYCsy2K/1.jpg)

从上图可以看出，DS 设计之初就考虑了高可用、多租户、可视化等高级功能，也支持扩展任务类型等，相比于其它工具来说，更适合企业内的复杂场景，可视化的操作界面也非常适合作为平台交给各部门自助使用。

## 2.安装和配置

官方文档：https://dolphinscheduler.apache.org/zh-cn/docs/1.2.1/user_doc/standalone-deployment.html

各组件版本：

| 后端版本        | 前端版本  |  ZK版本  | MySQL版本 |  安装节点 |  安装模式 |
| :--------:   | :-----:  | :----:  | :----: |  :----: |  :----: |
| 1.3.3     | 1.2.0 |   3.6.2     | 5.7.19 |  172.XX.XX.75 |  standalone |

官方文档步骤较为详细，这里说一下文档中需要补充/容易踩坑的地方：

## 2.1 安装Hadoop的需求

Hadoop是选装，选装，选装

①如果装了hadoop，可以使用hdfs存储上传的资源

②可以使用yarn cluster/client的方式来提交spark任务

因为我们使用的是spark的standalone模式，且考虑到tispark不需要额外的比较重的hadoop配置来帮助资源调度，因此对于①和②的解决方法如下：

①使用linux的文件系统来替代hdfs用于资源的上传和存储，配置如下：

```html
resourceStorageType="HDFS"
defaultFS="file:///opt/jobjars" 
yarnHaIps=""
singleYarnIp="yarnIp1"
resourceUploadPath="/opt/jobjars"
hdfsRootUser="hdfs"
$ chown –R dolphinscheduler. /opt/jobjars
```
注意：这里的目录在install之后会自动创建子目录dolphinscheduler和udfs以及resources两个次级目录

②由于目前（20201118）DS还不支持非yarn调度下的提交到spark群集的任务功能，对于非yarn调度下的spark任务只能以local的模式提交，即—master强制改为local[N]，因此，我们无法使用任务流中的spark节点部署任务
但是，因为在master机器上的linux命令行直接提交是可以提交到群集的，所以可以借助任务流的shell节点来完成这个操作
Linux上的提交命令example：

```html
/opt/spark-2.4.7/bin/spark-submit  --name "udf自定义开发测试" --master spark://172.xx.xx.75:7077  --class  Ehi.test.TimeStampDiff /opt/jobjars/tispark-examples-1.0.0-SNAPSHOT.jar
```

在工作流中的shell节点配置相同内容的脚本即可:

![1](https://i.postimg.cc/Y9RFc9hr/2.png)

实际测试下来和在linux命令行提交效果相同，集群也能接受任务，算是比较简单的不使用yarn的折中方案

![1](https://i.postimg.cc/nhMfBwv0/3.png)

## 2.2 Zookeeper的安装和配置

Zookeeper在安装时建议使用集群配置，分别装在3个不同的节点上
配置文件为/opt/zookeeper-3.6.2/conf/ zoo.cfg

```html
dataDir=/usr/local/zookeeper/data
clientPort=2181
admin.serverPort=9999
server.1=172.xx.xx.75:2182:2183
server.2=172.xx.xx.77:2182:2183
server.3=172.xx.xx.78:2182:2183
4lw.commands.whitelists=*
```
其余均为默认值，需要注意2181为客户端连接的端口，2182和2183分别是集群内部通信和选举leader的端口，需要保持一致，admin.serverPort默认8080与spark master节点的web UI端口冲突，需要改为别的，该参数只在3.5版本以上出现
另外，每个节点需要在data目录下创建myid文件，并对应server.N中的N值用于选举

DS关于zookeeper的配置

```html
zkQuorum="172.xx.xx.75:2181,172.xx.xx.77:2181,172.xx.xx.78:2181"
```

如果为单机伪集群部署，需要创建3个zoo.cfg文件

更改内容:

```html
clientPort=2181为2181~2183
server.1=172.xx.xx.80:2188:6001
server.2=172.xx.xx.80:2189:6002
server.3=172.xx.xx.80:2190:6003
```

之后，依次启动sh zkServer.sh ../conf/zoo1.cfg~ zoo2.cfg

DS中zkQuorum配置改为：

```html
zkQuorum="172.xx.xx.80:2181,1172.xx.xx.80:2182, 172.xx.xx.80:2183"
```

## 2.3 邮箱的配置

因为广州机房的机器无法连接外网，所以需要借助上海机房的邮件服务器的配置

```html
$ vim /etc/mail.rc
set from=SQLAlert
set smtp=192.xx.xx.228
set smtp-auth-user=SQLAlert
set smtp-auth-password=**
set smtp-auth=login
```
与此对应,在DS的配置文件中为

```html
mailServerHost="192.xx.xx.228"
mailServerPort="25"
mailSender="SQLAlert@1hai.cn"
mailUser="SQLAlert"
mailPassword="**"
starttlsEnable="false"
sslEnable="false"
sslTrust="192.xx.xx.228"
```

这里25是默认邮件服务器端口，可以通过telnet 192.xx.xx.228 25查看
mailUser是mtp-auth-user，mailPassword是smtp-auth-password
告警邮件发送以组为单位，可以将指定用户加入一个指定告警组，同一个用户只能拥有一个邮箱地址，在运行任务流时，也可以额外添加需要发送邮件的邮箱

## 2.4 更新DS配置

配置目录/opt/dolphinscheduler/dolphinscheduler-1.3.3/conf下的.properties文件均为install时的脚本生成，无需更改，
主要修改的配置文件为/opt/dolphinscheduler/dolphinscheduler-1.3.3/conf/config
和/opt/dolphinscheduler/dolphinscheduler-1.3.3/conf/env/ dolphinscheduler_env.sh
**每次修改配置文件后，先停止所有DS服务进程，再install即可**

```html
$ sh /opt/dolphinscheduler/dolphinscheduler-1.3.3/bin/stop-all.sh
$ sh /opt/dolphinscheduler/dolphinscheduler-1.3.3/install.sh
```

## 2.5 UI-Nginx配置(低于1.3.4版本)

UI包直接解压

如果有外网，直接通过install-dolphinscheduler-ui.sh安装，然后配置/etc/nginx/ nginx.conf

如果是内网，需要源码编译安装nginx，然后配置nginx.conf

nginx.conf配置如下：

```html
#user  nobody;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

#pid        logs/nginx.pid;


events {
    worker_connections  1024;
}


http {
    include       mime.types;
    default_type  application/octet-stream;

    #log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
    #                  '$status $body_bytes_sent "$http_referer" '
    #                  '"$http_user_agent" "$http_x_forwarded_for"';

    #access_log  logs/access.log  main;

    sendfile        on;
    #tcp_nopush     on;

    #keepalive_timeout  0;
    keepalive_timeout  65;

    #gzip  on;

	server {
    listen       8888;# 访问端口(自行修改)
    server_name  localhost;

    #charset koi8-r;

    #access_log  /var/log/nginx/host.access.log  main;

    location / {
        root   /opt/dolphinscheduler-ui/dist;      # 前端解压的dist目录地址(自行修改)
        index  index.html index.html;
    }
    location /dolphinscheduler {
        proxy_pass http://localhost:12345;    # 接口地址(自行修改)
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header x_real_ipP $remote_addr;
        proxy_set_header remote_addr $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_http_version 1.1;
        proxy_connect_timeout 4s;
        proxy_read_timeout 30s;
        proxy_send_timeout 12s;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    #error_page  404              /404.html;
    # redirect server error pages to the static page /50x.html
																				
    #
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   /usr/share/nginx/html;
    }
}
}
```

注意修改dist目录地址，并且接口地址需要为localhost

之后，重启DS服务和Nginx，观察12345和8888端口是否已经监听



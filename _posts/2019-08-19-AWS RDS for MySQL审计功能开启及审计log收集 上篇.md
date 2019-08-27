---
layout:     post
title:      AWS RDS for MySQL审计功能开启及审计log收集 上篇
subtitle:  	
date:       2019-08-19
author:     RC
header-img: 
catalog: true
tags:
    - AWS RDS for MySQL
    - Log rotation and collect
    - MariaDB Audit Plugin
---

### 正文
#### AWS RDS for MySQL审计功能开启步骤
##### 1.Create New Option Group
```
a.Name: mysql56-with-audit
b.Description: For MySQL 5.6 Version with MariaDB Audit Plugin
c.Engine: mysql
d.Major engine version: 5.6
```
##### 2.Add option MARIADB to the group
```
a.Option: MARIADB_AUDIT_PLUGIN
b.Parameters: 
SERVER_AUDIT_FILE_ROTATE_SIZE	 10485760 			B(10M)
SERVER_AUDIT_FILE_PATH		/rdsdbdata/log/audit/
SERVER_AUDIT_EVENTS* 		CONNECT,QUERY
SERVER_AUDIT_QUERY_LOG_LIMIT	1024 			B(1KB, max size of one record)
SERVER_AUDIT_FILE_ROTATIONS	30
SERVER_AUDIT				FORCE_PLUS_PERMANENT
SERVER_AUDIT_INCL_USERS 		N/A
SERVER_AUDIT_LOGGING		ON
SERVER_AUDIT_EXCL_USERS		rdsadmin	(still, the connect activity is always recorded for all users)
c.Apply immediately
```
##### 3.Associate the option group with the instance
```
a.Choose Modify the instance
b.In Database options, choose Option group mysql56-with-audit
c.Apply immediately
```
##### 4.Check variables on MySQL instance
```
mysql> SHOW GLOBAL VARIABLES LIKE '%server_audit%';
+-------------------------------+-----------------------+
| Variable_name                 | Value                 |
+-------------------------------+-----------------------+
| server_audit_events           | CONNECT,QUERY         |
| server_audit_excl_users       | rdsadmin              |
| server_audit_file_path        | /rdsdbdata/log/audit/ |
| server_audit_file_rotate_now  | OFF                   |
| server_audit_file_rotate_size | 10485760              |
| server_audit_file_rotations   | 30                    |
| server_audit_incl_users       |                       |
| server_audit_logging          | ON                    |
| server_audit_mode             | 1                     |
| server_audit_output_type      | file                  |
| server_audit_syslog_facility  | LOG_USER              |
| server_audit_syslog_ident     | mysql-server_auditing |
| server_audit_syslog_info      |                       |
| server_audit_syslog_priority  | LOG_INFO              |
+-------------------------------+-----------------------+
14 rows in set (0.00 sec)
```
##### 4.Tips
```
a.参数SERVER_AUDIT_EVENTS里是有一个table选项的：
TABLE: Log tables affected by queries when the queries are run against the database.
但是这个level对于MySQL是不支持的，对于MariaDB本身是支持的
实际上，在Query level：
Log the text of all queries run against the database (query execution time, client ip, username, query statement)
我们已经可以拿到受影响的table的信息，只不过是在SQL语句里面
b.对于不同的RDS for MysSQL实例，其modify的时间是不同的，如果instance长期处于modify的状态，可以手动重启，所以建议在访问低峰期进行enable
c.Audit log将保存在RDS for MySQL内部的log path下面，其大小之和不能超过数据库大小的2%
```
##### 5.Official Document
<https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.MySQL.Options.AuditPlugin.html>

#### 审计log收集方案
首先AWS并没有提供从RDS直接到S3的audit log的传输服务，
虽然可以开启instance的cloudwatch功能来进行变相存储，但是cloudwatch在absorb（收集RDS产生的audit log）阶段费用非常昂贵，并不适合长期大量的审计工作。
于是我们只能选择先从RDS下载需要的日志到EC的机器上，再上传到S3。**而这部分算是踩了个大坑**，AWS的官方文档中推荐我们使用CLI命令
```
aws rds download-db-log-file-portion
--db-instance-identifier <value>
--log-file-name <value>
[--cli-input-json <value>]
[--starting-token <value>]
[--page-size <value>]
[--max-items <value>]
[--generate-cli-skeleton <value>]
```
这个命令只要指定了instance名字，对应region，RDS中log的名字，以及输出格式和输出文件的名字就可以将RDS的audit log下载到EC的机器上。

然而在前期的stage实验中，我发现**从RDS通过这个CLI命令下载到本地的log的大小和RDS告诉我们的大小出入非常大**，从10M变成了2M，因为多次进行相同的下载都是这个结果，
所以排除了网络的原因，

那么是不是RDS的这个audit log已经坏掉了呢？

获取RDS audit log的另一个方法是直接从AWS console上进行下载，在这个case中，从console上下载下来的log的大小和设定的rotation大小一致，也和RDS describe出来的大小一致，所以排除了RDS本身日志出错的问题。

无奈之下我申请了AWS的online tech support，简单的描述完case，选好support类别，在排队等待了一会后，他们的技术人员从网页的对话窗口中开启了对话，

然而聊了一会我就发现显然这个老哥对RDS MySQL MARIADB Audit Plugin这块并不是很熟，他要求我重现这个case，于是我用他给的screen share插件给他演示了一次从RDS下载下来的audit log到本地的size decrease的情况。

这个老哥显然对这个情况也是一头雾水，在他检查内部网络的时候，我无意中发现下载下来的log文件内容里最后一行写了句**[Your log message was truncated]**

通过这个奇怪的关键词，他找到了github上一篇关于这种case的讨论帖子，原文链接：<https://github.com/aws/aws-cli/issues/2268>

原来这个丢失log内容的奇怪情况AWS的用户都有碰到过，此时他也承认这个是AWS CLI的bug，并答应在之后给我在邮件中提供详细的解决方案。

后来在他的邮件中确实详细的描述了另一个方法来下载log并强调将尽快让他们的技术部门解决这个bug：

**Admit bug and make up for:**

After our chat discussion, I have validated the issue nature with existing internal data. Through that, I would like to inform you that the API “DownloadDBLogFilePortion” is known to have some issues where the API is not able to download the complete log file some time and our internal team is aware of the same and actively working on it. We apologize for the inconvenience it might be causing you!

I understand that the limitation and behavior of the API “DownloadDBLogFilePortion” would be causing inconvenience to you, and I deeply apologize for the same! Please rest assured that our internal team is aware of the same, and are working on the fix to make out services better. Further in order to give this a higher priority, I have gone ahead and added a vote for this fix from your side, so that this can be looked into at the soonest. 

Having said that, changing any behavior or code change globally requires rigorous testing in order to maintain the stability of the infrastructure in general, and hence an ETA on the same cannot be provided at the moment. I hope you understand the same!

他在邮件中提供的另一个方法其实就是上面那个github帖子最新回复中一个网友声称是AWS提供的一个脚本程序，被另一个网友改成了他认为比较work的Python程序：<https://gist.github.com/joer14/4e5fc38a832b9d96ea5c3d5cb8cf1fe9>

然而这个程序必须提供access_key和secret_key才能work，而我们几乎不再使用key而是IAM role。

我们仔细看下有**[Your log message was truncated]**标记的地方的有问题log和完整log的比较:
```
< 20190813 12:30:11,ip-xxx-xx-x-xxx,favoriteadmin,xxx.xxx.xxx.xxx,7283,20335949,QUERY,favoritedb,'rollback',0
---
> 20190813 12:30:11,ip-xxx-xx-x-
>  [Your log message was truncated]
>
29578c29592,29594

< 20190813 15:07:06,ip-xxx-xx-x-xxx,favoriteadmin,xxx.xxx.xxx.xxx,39,20349895,QUERY,favoritedb,'rollback',0
---
> 20190813 15:07:06,ip-xxx-xx-x-xxx,favoriteadmin,xxx.xxx.xxx.xxx,39,20349895,QUERY,favoritedb,'rollback'
>  [Your log message was truncated]
> 
38419a38438
```
不难发现只要出现句话的地方的那一条record都被截取了或多或少的一段。

后来经过讨论我们决定该类record的数量如果不超过总数量的1%，就不会产生报警，而弥补方法就是手动去AWS console上下载对应log然后打包上传到S3。

关于具体的RDS audit log的rotation原理和相关Python程序细节，将在下一篇中分享。


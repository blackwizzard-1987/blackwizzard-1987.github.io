---
layout:     post
title:      MySQL通过binlog还原某张表到update之前
subtitle:  	
date:       2020-04-15
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - binlog
    - restore
---

## 1.问题由来

开发在上线一个JIRA更改了一张表的1700+条记录后间隔了几天发现线上报错，需要借助每日备份将这张表还原到当天更改前的状态

## 2.基本解决思路

通过当天0点10分的物理完整备份，还原到空余MySQL服务器
还原后，将这张被更改的表dump出来，导入到dev环境中供开发确认

a.如果满足需要，则用还原出来的库上的这张表替换掉线上的当前表；
b.如果不满足，则通过更改当天，从完整备份的时间点到更改前一刻的，**在binlog中找到与该表相关的更改，转换为sql**，然后导入到还原出来的新库中（应用更改，在上千条时效率应该高于人工寻找），再将更新后的表导入到线上进行替换。

## 3.具体步骤

```html
确认需要还原的表和所在库，以及大概更改时间
表: c***_c*****
库：y**_v****
所属项目：MySQL-e****
更改大致时间点：4月10日下午3点55分
问题发生时间点：4月14日下午
更该条目：2000+？
```

```html
找到该机器在10号0时10分的物理完整备份，
scp到空余MySQL服务器上，解压，应用日志，copy back
scp -P***** ***_2020-04-10_00_10_00_full.tar.gz root@****:/data/
****

通过备份还原后，启动MySQL，通过mysqldump导出该表
mysqldump -u*** -h*** -p --single-transaction --set-gtid-purged=off --master-data=2 -R -E --triggers --databases=*** --tables=*** > ***_20200414_restore.sql
```
在开发确认期间，我们也来看下那天对这张表的更新情况
主库上的binlog保留时间
![1](https://i.postimg.cc/2jPhh6Tf/Screenshot-4.png)

从主节点上将当天和之前一天以及之后一天的binlog拷到还原服务器上
![1](https://i.postimg.cc/hGy7jPh6/1.png)

通过grep寻找对该表的update操作
![1](https://i.postimg.cc/bNcSd5Ny/1595471073652.png)

可以看到，10号之前的9号18:49到10号当天4点均没有对该表的update操作

在10号当天4点后，到11号10：30之间，update该表的操作只在10号下午3点54分出现
![1](https://i.postimg.cc/DZ4mwr94/15954711437563.png)

Update的条数共计1713条

由此可以得出结论：**当天完整备份之后到更改内容之前，该表上没有其他更改**
即完整备份还原出来的该表一定是能满足条件的
这一点在后续开发确认后也被印证了

因此，先修改导出的sql文件中的表名，然后导入到线上，再rename将旧表替换为线上表即可
![1](https://i.postimg.cc/Pq9r9LCX/15954712316130.png)

## 4.另一种情况

那么如果在完备到更改之间，有其他更新，则需要如下操作
找到2020-04-10 00:10:00 到2020-04-10 15:54:00 之间，**最后**更改该表的binlog的pos
```html
mysqlbinlog --no-defaults -vv --base64-output=decode-rows binlog.000360 --start-datetime='2020-04-10 00:00:00' | grep -i -C 10 'UPDATE `***`.`***`'
```
得到时间点2之前最后更改该表的事务的pos N

然后，将这段binlog转为SQL
```html
mysqlbinlog --no-defaults binlog.000360 --start-datetime='2020-04-10 00:00:00' --stop-position=N -d *** --skip-gtids=true > restore.sql
```

最后，将这些更改应用回之前还原出来的MySQL
```html
mysql > source restore.sql;
```

此时，在空余MySQL服务器上的表已经从4月10号0点10分备份出来的状态到了4月10号15点54分错误更新前的状态

同情况1，再替换掉线上的该表即可

## 5.总结

每日的备份非常重要，包括主/写节点上的binlog日志的保留
在更新大量记录之前（超过1K），需要进行备份以防万一回滚
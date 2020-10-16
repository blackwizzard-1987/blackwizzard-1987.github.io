---
layout:     post
title:      TiDB DM同步DDL错误及解决思路
subtitle:  	
date:       2020-10-17
author:     RC
header-img: 
catalog: true
tags:
    - TiDB
    - DM
    - 故障处理
---

## 正文

上午10时11分，收到邮件等告警，TiDB DM同步状态为暂停已经超过20分钟：

![1](https://i.postimg.cc/2Snh23Xf/1.png)

因为我们的DM上游数据源是MySQL, 这个时间点初步判断很有可能是执行的一条DDL更改表字段类型的语句引起的DM同步失败。

登录DM-master服务器，使用dmctl查看同步状态：

```html
cd /home/tidb/dm-ansible/resources/bin/
./dmctl --master-addr dm-masterIP:8261

query-status worker-task-name
```

从输出结果可以看到几个重要信息：

![1](https://i.postimg.cc/WzDJr4JC/2.png)

1.DM的这个worker任务确实不工作了，同步状态为Paused

2.造成中断的原因是DDL语句无法在tidb中回放，错误信息为：
Error 8200: Unsupported modify column: type json not match origin varchar(300)

3.中断处的binlog信息binlog|000002.000038:271519382

这个DDL语句显然是之前在上游MySQL执行的将字段从varchar改成json的操作，本质应该是charset 的变换，而tidb本身是支持json格式的，那么解决问题的思路就很简单了：

1.在tidb对应表中新建字段为modify之后的格式和名字，并且在旧字段顺序之后

2.同步旧字段内容到新字段，drop旧字段，rename新字段为旧字段

3.通过dmctl的sql-skip，跳过该条DDL，resume task继续复制

操作如下：

```html
-- on tidb
> alter table goods add column goods_content_new json NOT NULL comment '商品内容' after goods_content;
> update goods set goods_content_new = goods_content;
> alter table goods drop column goods_content;
> alter table goods change goods_content_new goods_content json NOT NULL comment '商品内容';
> desc goods;
```

```html
-- in master dmctl
再次确认binlog位置
>> query-error worker-task-name
"failedBinlogPosition": "binlog|000002.000038:271519382"
>> sql-skip --worker=workerIP:8262 --binlog-pos=binlog|000002.000038:271519382 worker-task-name
>> resume-task --worker=workerIP:8262 worker-task-name
>> query-error worker-task-name
>> query-status worker-task-name
```

```html
-- on tidb
select goods_content from goods order by create_time desc;
```

![1](https://i.postimg.cc/rF159KH2/3.png)

可以看到worker状态已变为running，binlog位置不断变化，该表的字段新增值入表正常，问题解决。

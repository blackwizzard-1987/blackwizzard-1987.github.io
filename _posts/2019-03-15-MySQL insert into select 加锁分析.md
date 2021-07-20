---
layout:     post
title:      MySQL insert into select 加锁分析
subtitle:  	
date:       2019-03-15
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - 锁等待
    - 数据迁移
---

### 背景

线上某个库因历史原因，造成两个系统共用同一个数据库，代码相互交织，系统间耦合度过高。随着业务的不断快速发展。技术包袱变得越来越重。开发维护难度变高，开发效率变低。影响了业务的发展速度和用户的使用体验。经开发协商后，决定先从数据入手，将部分表(31张)同步到新库中，线上双写一段时间后进行切换和分离。

这个需求有两点需要考虑：

- 原库的表需要保留，因此不能alter table ... rename to ... 直接换库

- 使用insert into ... select * from ... ，需要考虑copy表数据过程中的DML同步问题

本文主要讨论第二点在不同数据库隔离级别和参数设置下的表现

### RR级别

测试方法：

在执行insert into db2.tb1 select * from db1.tb1 期间，手动执行DML语句，观察锁等待情况

```html
按默认排序(主键)：
insert into data_temp.tb1 select * from db2.tb1 order by id asc;
insert into data_temp.tb1 select * from db2.tb1 order by id desc;
```

结果：

在默认(不加排序字段)情况下，按主键倒序或者正序进行导入操作，**会锁原表tb1，但是是按扫描顺序依次上锁，逐步地锁定已经扫描过的记录**

> (正序)即T1时刻，靠前的id所在的行已经不能进行更新了，靠后的id还可以进行DML操作，而T2时刻，靠后的id也不能进行DML操作了

```html
按其他字段排序(非主键)：
insert into data_temp.tb1 select * from db2.tb1 order by carno asc;
insert into data_temp.tb1 select * from db2.tb1 order by carno desc;
```

观察加锁情况：

![1](https://i.postimg.cc/brXL8ghG/1.png)

结果：

在加排序字段(非主键)情况下，**一开始就会锁原表tb1，直到导入操作结束**

### RC级别

我们默认binlog_format =row

测试方法同上

结果：

在所有情况下，**tb1上一直没有锁，DML操作可以并发**

### 结论

RR级别下，按主键排序进行导入，则X锁会按主键扫描顺序，从第一行/最后一行开始锁到最后/最前。

RR级别下，按非主键排序进行导入，则表上一直会有X锁直到导入完成。

RC级别+binlog_format = ROW时，导入期间表上没有X锁，DML可以并发进行，但导入期间的DML不会同步到新表上，一致性位点在导入操作开始时。

### 结果

最终我们选择了影响最小的第三种情况，在业务低峰期进行操作，数据导入新表后开发通过比对将差异部分手动重新导入。


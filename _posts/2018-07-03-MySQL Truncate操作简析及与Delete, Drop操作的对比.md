---
layout:     post
title:      MySQL Truncate操作简析及与Delete, Drop操作的对比
subtitle:  	
date:       2018-07-03
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - 删除操作
    - DDL
---

本文主要简单分析了MySQL数据库在删除数据操作时的三种方式以及它们的主要区别

### Truncate

根据官方文档，truncate命令有以下几个特征：

- 类似于delete删除表中所有数据，或者等价于drop table再create table

- 是一个隐式(implicit)提交，因此无法进行回滚，不会产生redo和undo log，也因此提高了执行速度

- 只要原表的表定义是有效的，即使数据和索引文件损坏，也可以执行truncate

- 其返回值均为"0 rows affected"，实际上不包含任何含义

- 在任何binlog_format下只记录statement，因此无法通过binlog回滚

- 赋予用户truncate权限时，需要给与drop权限

### 三者的主要区别

- 执行速度上：drop > truncate >> DELETE

- 操作类型上：

```html
DML: Delete
DDL: Drop, Truncate
```

- 执行后释放空间上：

| 删除方式  | 是否立即释放空间  | 是否可以找回 |  extra |
| :------------: |:---------------:| :-----:| :-----:|
|    Delete   | 否 | 是 | 释放空间需要额外执行optimize table，可以通过binlog反向解析找回|
| Drop      | 是 | 是 |通过开源工具undrop-for-innodb找回|
| Truncate | 是 | 是 |通过开源工具undrop-for-innodb找回|

- 操作对象上：

```html
Truncate: 表
Delete, Drop: 表，视图等
```

-其他

| 删除方式  | 是否保留表结构/索引  | 是否保留自增值 |  是否触发trigger |
| :------------: |:---------------:| :-----:| :-----:|
|    Delete   | 是 | 是(重启8.0+)| 是|
| Drop      | 否 | 否 | 否|
| Truncate | 是 | 否(将固定重置为1) |否|


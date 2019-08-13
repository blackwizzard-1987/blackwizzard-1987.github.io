---
layout:     post
title:      Redshift新增修改VARCHAR类型字段长度的功能
subtitle:  	
date:       2019-08-13
author:     RC
header-img: 
catalog: true
tags:
    - AWS Redshift
    - 数据仓库
    - 经验分享
---

### 正文
最近有一个DBchange要求增大几个redshift表中的varchar类型字段，因为印象中AWS的redshift一直是不支持alter字段类型操作的，并且该表非常大（将近155亿条记录），我们的cluster的disk space也不太够，
所以之前用的笨办法：
```
1.导出原表的structure，修改需要更改的字段的类型，以此新建符合要求的新表，最后将原表数据insert到新表中
2.在原表里新增符合要求的新字段，将原表的原字段数据update到新字段中，再删除原表的原字段
```
是行不通了。

后来在Stack Exchange上看到最新的评论发现AWS（在最近）已经enable了redshift中VARCHAR类型字段的**修改长度**功能，原文如下：
```
AWS Redshift is now possible to alter ONLY VARCHAR column but under these conditions:

You can’t alter a column with compression encodings BYTEDICT, RUNLENGTH, TEXT255, or TEXT32K.
You can't decrease the size less than maximum size of existing data.
You can't alter columns with default values.
You can't alter columns with UNIQUE, PRIMARY KEY, or FOREIGN KEY.
You can't alter columns inside a multi-statement block (BEGIN...END).
```
AWS相关文档说明：
<https://docs.aws.amazon.com/redshift/latest/dg/r_ALTER_TABLE.html>

于是
```
alter table xxx.xxx alter column xxx type varchar(256);
```
大概过了十几分钟就修改完成了




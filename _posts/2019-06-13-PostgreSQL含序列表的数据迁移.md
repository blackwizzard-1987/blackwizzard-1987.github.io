---
layout:     post
title:      PostgreSQL含序列表的数据迁移
subtitle:  	
date:       2019-06-13
author:     RC
header-img: 
catalog: true
tags:
    - PostgreSQL
    - DBA 
    - 经验分享
---

### 题外话
这篇文章是我写的第一篇中文博客，其中涉及到jekyll无法预览中文文件的问题，虽然直接提交到github上可以正常解析，但无法再本地进行预览还是太不方便了。
这个问题主要是因为博客的markdown文件使用了中文文件名，jekyll无法正常解析出现乱码。

解决方法是找到Ruby的安装目录
```
\Ruby22-x64\lib\ruby\2.2.0\webrick\httpservlet下的filehandler.rb文件
```
在如下两处添加编码语句:

```
path = req.path_info.dup.force_encoding(Encoding.find("filesystem"))
path.force_encoding("UTF-8") # 加入编码
```
```
break if base == "/"
base.force_encoding("UTF-8") # 加入编码
```
### 正文
数据迁移可以说是DBA平常而又重要的工作之一，而涉及到序列的数据迁移，则需要更加细心，因为在数据迁移过程中，很容易碰到表和序列不匹配的情况，如果表的序列
填充id最大值大于序列的next值，将导致无法继续插入数据的情况，从而影响应用的正常运行。因此，当我们完成数据迁移后（包括冷备份和停业务的导出导入），对核心
表的序列检查是必要的，至少要以大于等于max（ID），一般也是序列的last_value值为开始，这样才不会出现后面insert时nextval()比当前id小的情况导致无法插入记录。

下面介绍一个工作中的简单迁移作为例子：

1.在还原源数据库的表到目标数据库时，发现报错ERROR: relation "xxx_sub_id_seq" does not exist

2.检查发现该报错表中的一个字段的default值是nextval()函数返回的序列值

3.检查发现源数据库中的该表的该字段的最大值，以及对应序列的last_value值一致
```
DB1=# select max(xx_sub_id) from sa_addr_id;
   max   
---------
 7270236
(1 row)

TnGeo-Here-Data=# \d xxx_sub_id_seq
     Sequence "common.xxx_sub_id_seq"
    Column     |  Type   |            Value            
---------------+---------+-----------------------------
 sequence_name | name    | xxx_sub_id_seq
 last_value    | bigint  | 7270236
 start_value   | bigint  | 1
 increment_by  | bigint  | 1
 max_value     | bigint  | 9223372036854775807
 min_value     | bigint  | 1
 cache_value   | bigint  | 1
 log_cnt       | bigint  | 3
 is_cycled     | boolean | f
 is_called     | boolean | t
Owned by: common.sa_addr_id_bak.xx_sub_id
```
4.在目标数据库中的对应schema新建同名序列，并以3中的last_value为start_value
```
create sequence xxx_sub_id_seq INCREMENT by 1 MINVALUE 1 NO MAXVALUE start with 7270236;
```

5.重新单独导入该表，没有报错，开发后续插入数据正常





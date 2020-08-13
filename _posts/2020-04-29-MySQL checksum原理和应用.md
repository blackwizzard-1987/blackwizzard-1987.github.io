---
layout:     post
title:      MySQL checksum原理和应用
subtitle:  	
date:       2020-04-29
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - Percona Toolkit
    - checksum
---

## 1.checksum的使用场景

① 在主从复制中对某些重要的表进行一致性检查

② 备份还原/迁移后源端与目标端表一致性检查

## 2.checksum语法

```html
CHECKSUM TABLE tbl_name [, tbl_name] ... [QUICK | EXTENDED]
```

默认值：EXTENDED

含义：在EXTENDED模式下，整个表被一行一行地读取，并计算校验和。**对于大型表，这是非常慢的。**

选项值：QUICK

含义：报告活性表校验和，否则报告NULL。这是非常快的。活性表通过指定CHECKSUM＝1表选项启用，目前只支持用于MyISAM表。


## 3.checksum原理

Checksum table计算返回值的逻辑大致如下：

```html
ha_checksum crc= 0;
foreach(row in table)
{
  row_crc= get_crc(row);
  crc+= row_crc;
}
return crc;
```

从这段逻辑可以看出：

1. checksum table返回的值只与表的总行数以及每行内容有关，与读取行的顺序无关
因此，因为delete等操作造成的逻辑导出后，两个表的全表扫描顺序不同，是不会影响checksum table的结果的

2. 与使用的引擎无关

3. 与是否有索引无关。row_crc只用行本身的数据来计算，并不包括索引数据。

**结论：如果两个表里面的数据一样，表结构（列内容和顺序一样），操作系统一样，MySQL版本一致，是能够保证checksum的结果相同的。**


> 注：如果MySQL版本不一致，则checksum table的返回值对于某些含某些字段的表会不一致，比如datetime，在5.6.4以前是固定8字节，之后的版本改变了存储格式，变成了5+N个字节，与精度有关。

row_crc在计算时的逻辑：

```html
switch (f->type()) {
                case MYSQL_TYPE_BLOB:
                case MYSQL_TYPE_VARCHAR:
                case MYSQL_TYPE_GEOMETRY:
                case MYSQL_TYPE_BIT:
                {   
                  String tmp;
                  f->val_str(&tmp);
                  row_crc= my_checksum(row_crc, (uchar*) tmp.ptr(),
                           tmp.length());
                  break;
                }   
                default:
                  row_crc= my_checksum(row_crc, f->ptr, f->pack_length());
                  break;
              }   
```

从这段逻辑可以看出：

1. 在个row计算row_crc时，是每个字段依次计算的。但计算过程中会将上一个字段的结果作为计算下一个值的输入。因此，字段顺序会影响统计结果。

2. 字段内容相同，类型不同时，会影响checksum结果。对于变长字段类型如varchar，计算的是实际长度因此不会影响，但是char（20）和char（25），int和bigint，即使看到的内容相同，得到的checksum值也不同。

其他因素：字符集影不影响checksum值，结论是如果字段的unhex()(将十六进制的字符串转换为原来的格式)值相同，则统计值一定相同。

## 4.常用情境下的checksum脚本

假设还原前后的库为test，需要得到还原前后该库所有表是否一致，

思路为得到源端所有表的checksum值->文件1

得到目标端所有表的checksum值->文件2

diff比较两个文件即可

```html
#!/bin/sh 

table_list=`/usr/local/mysql/bin/mysql -h** -uroot -p123 -A -N << EOF | tail -n +3
    use test;show tables;
EOF`

for i in ${table_list}
do
        table_cs=`/usr/local/mysql/bin/mysql -h** -uroot -p123 -A -N -D test -e "checksum 
table ${i};"`
    echo ${table_cs} >> table_checksum.txt
done
```

>（-A 不预读数据库信息打开数据库，避免表过多造成打开缓慢；-N 不返回查询结果的列名）

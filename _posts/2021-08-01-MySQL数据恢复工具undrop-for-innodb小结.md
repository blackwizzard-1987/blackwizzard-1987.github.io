---
layout:     post
title:      MySQL数据恢复工具undrop-for-innodb小结
subtitle:  	
date:       2021-08-01
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - undrop-for-innodb
    - 数据恢复
---

### 工具简介

UnDrop for InnoDB是一套开源的针对**MySQL innodb**表的数据恢复工具，也被制作者称为TwinDB data recovery toolkit，它从底层原理出发，可以在无备份的情况下，对各个故障场景进行数据恢复，如：

- Drop/Truncate table

- 误删表中数据

- 磁盘/文件系统损坏(脏数据)

- 丢失用户表ibd/frm文件

### 工具原理浅析

介绍工具原理之前，我们先简单了解下innodb系统表，或者称为innodb数据字典表，一共有4张这样的表，分别是SYS_TABLES， SYS_INDEXES， SYS_COLUMNS， SYS_FIELDS。它们有如下特点：

- 是系统的内部表，用于维护用户表的各种信息

- 存储在系统表空间ibdata1中的固定位置(**固定页**)上，对用户不可见

- 包含比较重要的信息，比如元数据(**表结构**)信息，**主键索引所拥有的所有数据页的页号**

我们知道，要恢复诸如drop table之类的高危操作，我们需要得到原表的表结构和表数据。

**对于表结构**，我们可以从系统表SYS_COLUMNS(主要)得到：

```html
 CREATE TABLE `SYS_COLUMNS` (
  `TABLE_ID` bigint(20) unsigned NOT NULL,
  `POS` int(10) unsigned NOT NULL,
  `NAME` varchar(255) DEFAULT NULL,
  `MTYPE` int(10) unsigned DEFAULT NULL,
  `PRTYPE` int(10) unsigned DEFAULT NULL,
  `LEN` int(10) unsigned DEFAULT NULL,
  `PREC` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`TABLE_ID`,`POS`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
```

其中TABLE_ID与SYS_TABLES中的一致， POS是字段在表中的相对位置(排列序号)，NAME是字段的名字，MTYPE和PRTYPE相对不重要(innodb的历史遗留产物)， LEN是字段占用的最大长度(单位：字节)，PREC是某些类型字段的精度(默认0)。

**对于表数据**，根据innodb表B+树的特性，理论上，我们只要得到主键索引所拥有的所有数据页的页号，再通过innodb page的格式去分别解析每个包含的数据页，进行拼接，就可以得到所有可以恢复的数据。

而系统表SYS_INDEXES恰好包含了这个信息：

```html
CREATE TABLE `SYS_INDEXES` (
  `TABLE_ID` bigint(20) unsigned NOT NULL DEFAULT '0',
  `ID` bigint(20) unsigned NOT NULL DEFAULT '0',
  `NAME` varchar(120) DEFAULT NULL,
  `N_FIELDS` int(10) unsigned DEFAULT NULL,
  `TYPE` int(10) unsigned DEFAULT NULL,
  `SPACE` int(10) unsigned DEFAULT NULL,
  `PAGE_NO` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`TABLE_ID`,`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;
```

其中TABLE_ID为SYS_TABLES中的一致，ID是非常重要的一个字段，它表示**对应的索引所拥有的主键/数据页 or 二级索引/索引页的页号信息**，NAME是索引的名字，N_FIELDS指索引所包含的字段个数，TYPE不重要，SPACE指innodb的表空间识别号表示索引存储的地址，PAGE_NO指索引的根节点所在页的页号。

整体解析过程大致如下(图片源于网络)：

![1](https://i.postimg.cc/jdsrcwsz/1.png)

而innodb的数据页在server端删除等操作后，会先被标记(mark)为deleted，在purge线程清理后，可以被重写，在新的数据写入之前，被删除的数据是还保留在数据页上的，因此可以第一时间通过undrop-for-innodb进行解析和恢复。

### 工具优缺点

优点：

- 在无备份情况下，能够恢复大部分表结构(不包括二级索引和特定字段精度等)和所有数据(所有主键索引拥有的数据页都未被重写/删除)

- 在特定情况下(脏数据，磁盘坏块等)比使用备份+binlog还原的方式更加灵活，恢复数据效率更高

缺点：

- 对于恢复环境要求比较苛刻，需要配合做数据库所在磁盘镜像或者设置部分只读，如果数据页被删除或者复写将无法恢复数据，同时，如果脏数据/坏块中包含了数据页的一些重要元数据信息，也将无法被工具识别和解析，在线上系统较繁忙的情况下难以保证数据恢复率

- 对于大表的恢复较为繁琐，需要挨个解析所有的数据页得到各个字段的数据并拼接为SQL insert回原表

### 工具安装

```html
$ git clone https://github.com/twindb/undrop-for-innodb.git 
$ make
$ gcc `$basedir/bin/mysql_config --cflags` `$basedir/bin/mysql_config --libs` -o sys_parser sys_parser.c
# $basedir为MySQL配置文件中的basedir = /usr/local/mysql
```

此时，工具目录下将有stream_parser，c_parser，sys_parser这三个重要的恢复工具

![2](https://i.postimg.cc/3NQfRK5Z/2.png)

其他比较重要的目录/文件：

- test.sh && recover_dictionary.sh && fetch_data.sh 是测试的脚本，可以看下里面的逻辑理解工具的用法

- dictionary 里面是模拟 innodb 系统表结构写的 CREATE TABLE 语句

- sakila 是一些 SQL 语句，用来测试用

- include 是从 innodb 拿出来的一些用到的头文件和源文件

### 工具使用(恢复drop操作)

我们创建一张简单的test表，插入5条数据，来进行恢复测试

![3](https://i.postimg.cc/VL1HPLFf/3.png)

![4](https://i.postimg.cc/GmgMDPnt/4.png)

该表包含一个主键字段id int和一个普通字段name varchar(20)， checksum值为684827261，已经通过drop操作删除

#### 恢复表结构

因为表结构在innodb数据字典中含有信息，因此我们只需要解析innodb的系统表空间文件，再提取出对应表的元信息即可

```html
$ ./stream_parser -f /data/mysql/data/ibdata1
```

执行完毕后将在工具根目录下生成pages-ibdata1文件夹，其中包含blob等大字段的数据页和普通索引页，它们都以页为单位按序号排列：

![5](https://i.postimg.cc/MHKcSQ32/5.png)

接下来，因为innodb系统表的位置在系统表空间上是固定的，因此我们只需要通过工具提取特定页的内容，即可得到对应表的元数据信息：

```html
$ ./c_parser -4Df pages-ibdata1/FIL_PAGE_INDEX/0000000000000001.page -t dictionary/SYS_TABLES.sql | grep 'tt/test'
参数解析：
4 表示文件格式是 REDUNDANT，系统表的格式默认值。另外可以取值 5 表示 COMPACT 格式，6 表示 MySQL 5.6 格式
D 表示只恢复被删除的记录
f 后面跟着文件
t 后面跟着 CREATE TABLE 语句，需要根据表的格式来解析文件
编号为0000000000000001的系统表空间上的页包含了各个表的表字典信息
```

执行结果如下：

```html
0000612840DE	360000002B01EC	SYS_TABLES	"tt/test"	3263	2	33	0	80	""	1808
0000612840DE	360000002B01EC	SYS_TABLES	"tt/test"	3263	2	33	0	80	""	1808
SET FOREIGN_KEY_CHECKS=0;
LOAD DATA LOCAL INFILE '/opt/undrop-for-innodb-develop/dumps/default/SYS_TABLES' REPLACE INTO TABLE `SYS_TABLES` CHARACTER SET UTF8 FIELDS TERMINATED BY '\t' OPTIONALLY ENCLOSED BY '"' LINES STARTING BY 'SYS_TABLES\t' (`NAME`, `ID`, `N_COLS`, `TYPE`, `MIX_ID`, `MIX_LEN`, `CLUSTER_NAME`, `SPACE`);
-- STATUS {"records_expected": 1464, "records_dumped": 141, "records_lost": true} STATUS END
```

其中比较重要的是**系统表SYS_TABLES的ID值3263**，我们将通过这个表ID从其他三张系统表获取表的其他信息

```html
$ ./c_parser -4Df pages-ibdata1/FIL_PAGE_INDEX/0000000000000003.page -t dictionary/SYS_INDEXES.sql  | grep '3263'
# 同样为固定页的系统表，grep 3263是为了找到对应表的索引信息
```

执行结果如下：

```html
0000612840DE	360000002B0145	SYS_INDEXES	3263	3590	"PRIMARY"	1	3	1808	4294967295
SET FOREIGN_KEY_CHECKS=0;
LOAD DATA LOCAL INFILE '0000612840DE	360000002B0145	SYS_INDEXES	3263	3590	"PRIMARY"	1	3	1808	4294967295
/opt/undrop-for-innodb-develop/dumps/default/SYS_INDEXES' REPLACE INTO TABLE `SYS_INDEXES` CHARACTER SET UTF8 FIELDS TERMINATED BY '\t' OPTIONALLY ENCLOSED BY '"' LINES STARTING BY 'SYS_INDEXES\t' (`TABLE_ID`, `ID`, `NAME`, `N_FIELDS`, `TYPE`, `SPACE`, `PAGE_NO`);
-- STATUS {"records_expected": 1245, "records_dumped": 138, "records_lost": true} STATUS END
```

其中**系统表SYS_INDEXES的ID 3590表示PRIMARY key所拥有的数据页的页号**，我们将根据这个ID去解析表的数据页得到表数据

```html
$ ./c_parser -4Df pages-ibdata1/FIL_PAGE_INDEX/0000000000000002.page -t dictionary/SYS_COLUMNS.sql | grep 3263
# 同理，从固定页上获取表中字段的信息
```

执行结果如下：

```html
SET FOREIGN_KEY_CHECKS=0;
LOAD DATA LOCAL INFILE '/opt/undrop-for-innodb-develop/dumps/default/SYS_COLUMNS' REPLACE INTO TABLE `SYS_COLUMNS` CHARACTER SET UTF8 FIELDS TERMINATED BY '\t' OPTIONALLY ENCLOSED BY '"' LINES STARTING BY 'SYS_COLUMNS\t' (`TABLE_ID`, `POS`, `NAME`, `MTYPE`, `PRTYPE`, `LEN`, `PREC`);
-- STATUS {"records_expected": 7246, "records_dumped": 2877, "records_lost": true} STATUS END
0000612840DE	360000002B0182	SYS_COLUMNS	3263	0	"id"	6	1283	4	0
0000612840DE	360000002B01B7	SYS_COLUMNS	3263	1	"name"	12	14680079	80	0
```

> 这里系统表SYS_COLUMNS中是包含了特定字段的精度的，但是最后通过工具还原出的表结构是没有的

```html
$ ./c_parser -4Df pages-ibdata1/FIL_PAGE_INDEX/0000000000000004.page -t dictionary/SYS_FIELDS.sql | grep 3590
# 最后，从固定页上获取表中索引上的字段的信息
```

执行结果如下：

```html
0000612840DE	360000002B0110	SYS_FIELDS	3590	0	"id"
0000612840DE	360000002B0110	SYS_FIELDS	3590	0	"id"
SET FOREIGN_KEY_CHECKS=0;
LOAD DATA LOCAL INFILE '/opt/undrop-for-innodb-develop/dumps/default/SYS_FIELDS' REPLACE INTO TABLE `SYS_FIELDS` CHARACTER SET UTF8 FIELDS TERMINATED BY '\t' OPTIONALLY ENCLOSED BY '"' LINES STARTING BY 'SYS_FIELDS\t' (`INDEX_ID`, `POS`, `COL_NAME`);
-- STATUS {"records_expected": 1848, "records_dumped": 418, "records_lost": true} STATUS END
```

得到index包含的字段名字和在索引中的位置

之后，在测试库中新建一个recover库，并在这个库中通过dictionary下的系统表建表SQL创建4张模拟的系统表，然后将之前解析出的内容插入到对应的系统表中(需要去重)，再使用sys_parser恢复出建表语句：

```html
$ ln -s /Installation/mysql-5.7.19-linux-glibc2.12-x86_64/lib/libmysqlclient.so.20 /usr/local/lib/libmysqlclient.so.20
$ cat /etc/ld.so.conf
include ld.so.conf.d/*.conf
/usr/local/lib
/sbin/ldconfig -v
$ ./sys_parser -h**** -uDBA_RC -p'****' -d recover tt/test
CREATE TABLE `test` (
  `id` int(11) NOT NULL,
  `name` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB
```

> 可以看到，innodb 系统表里面存的数据相比 frm 文件是不足的，比如 AUTO_INCREMENT, DECIMAL 类型的精度信息都会缺失，也不会恢复二级索引，外键等；但实际上，在后三张系统表的解析结果中，这些信息都是包含的

#### 恢复表数据

因为默认开启了innodb_file_per_table，因此我们只能从**MySQL的data目录所在的磁盘**进行innodb页的解析得到主键所拥有的数据页：

```html
$ cat /etc/my.cnf | grep datadir
datadir=/data/mysql/data
$ df -h
Filesystem           Size  Used Avail Use% Mounted on
/dev/mapper/cl-root  197G  169G   29G  86% /
$ ./stream_parser -f /dev/mapper/cl-root -s 1G -t 197G
# -f 需要解析的innodb文件/系统盘符
# -s 解析时使用的磁盘缓存大小
# -t 指定innodb文件/系统盘符的大小
Worker(0): 1.52% done. 2021-07-28 18:24:13 ETA(in 03:07:32). Processing speed: 17.655 MiB/sec
```

可以看到这个解析是比较慢的，因为是按照innodb的格式去逐个判断并输出符合格式的页，但是因为本次测试中，从SYS_INDEXES得到的数据页只有一个，页号为3590，因此我们只需要关心解析出来的编号为3590的page就行了。

在进度达到20%左右时，0000000000003590.page已经被工具解析出来了，因此我们停止解析剩下的磁盘内容，直接恢复数据：

```html
$ ./c_parser -6f ./pages-cl-root/FIL_PAGE_INDEX/0000000000003590.page -t test.sql 
-- Page id: 3, Format: COMPACT, Records list: Valid, Expected records: (5 5)
00006127139F	B2000009140110	test	1	"sda"
0000612840D1	AD000005110110	test	2	"kkk"
0000612840D2	AE000000330110	test	3	"ytu"
0000612840D7	B1000011450110	test	4	"kweqw"
0000612840D9	B3000005190110	test	5	"kw34"
SET FOREIGN_KEY_CHECKS=0;
LOAD DATA LOCAL INFILE '/opt/undrop-for-innodb-develop/dumps/default/test' REPLACE INTO TABLE `test` CHARACTER SET UTF8 FIELDS TERMINATED BY '\t' OPTIONALLY ENCLOSED BY '"' LINES STARTING BY 'test\t' (`id`, `name`);
-- STATUS {"records_expected": 5, "records_dumped": 5, "records_lost": false} STATUS END
-- Page id: 3, Found records: 5, Lost records: NO, Leaf page: YES
```

此时，该表的数据也已经恢复了，我们将其拼接为insert SQL， 还原到recover数据库中的test表中，然后checksum，得到的值和drop之前是相同的：

![6](https://i.postimg.cc/pLGBRYJ2/6.png)

### 工具使用(恢复坏块/磁盘脏写)

脏写的恢复步骤和drop操作大致一样，也是先得到表结构和SYS_INDEXES的ID，只不过最后还原出的数据中，有一部分是被脏写的数据，已经无法使用。

在这一步中，如果被脏写的行是innodb page的比较重要的元数据信息，那么stream将无法检测出innodb页或者c_parser无法解析出页中正确的数据。

> 这种恢复方式是寄托在重要页元数据和行元数据没有被脏写的前提下的，由于重要的元数据所占比例较小，如果每个字节被脏写的概率相同，那么数据的可恢复性还是比较可观的

### 小结

如果要使用该工具进行恢复，需要第一时间将重要的数据拷贝出来，比如使用dd命令制作磁盘的镜像，在数据页没有被复写/清理，以及脏写没有损坏重要的页元数据和行元数据情况下，恢复率还是比较可观的，但是恢复时间会比较长，是比较精细的操作，适合一些没有备份的情况下的小规模的数据恢复。

### 参考

[淘宝数据库内核组博客](http://mysql.taobao.org/monthly/2017/11/01/)

[工具作者分析innodb系统表](https://twindb.com/innodb-dictionary/)

[其他](https://weibo.com/1933424965/H3qIu0JYo?from=page_1005051933424965_profile&wvr=6&mod=weibotime&type=comment#_rnd1627969209228)

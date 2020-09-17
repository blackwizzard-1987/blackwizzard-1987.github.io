---
layout:     post
title:      pt-online-schema-change原理和使用小结
subtitle:  	
date:       2020-03-17
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - OSC
    - DDL
---

## 1.pt-online-schema-change使用背景

MySQL的原生Online DDL 从5.6版本开始出现，5.7版本优化，8.0版本出现了新的特性，但仍是DBA的难点，痛点之一。

其中，几种常见的Online DDL需求如下：

·增加新列（ADD COLUMN）

·修改列定义（MODIFY COLUMN）

·增加/删除索引（ADD/DROP INDEX）

MySQL的原生Online DDL在使用时，ALGORITHM可以指定的几种方式：

```html
COPY ，会生成临时表，将原表数据逐行拷贝到新表中，在此期间会阻塞DML
```

```html
INPLACE，无需拷贝全表数据到新表，但可能还是需要INPLACE方式重建整表。这种情况下，在DDL的初始准备和最后结束两个阶段时通常需要加MDL锁，除此外，DDL期间不会阻塞DML
```

```html
INSTANT，只需修改数据字典中的元数据，无需拷贝数据也无需重建整表，同样，也无需加排他MDL锁，原表数据也不受影响。整个DDL过程几乎是瞬间完成的，也不会阻塞DML。这个新特性是8.0.12引入的，仅限于少数几种情况才可以使用：
·在表最后新增一个字段
·新增或删除虚拟列
·新增或删除字段默认值
·修改索引类型
·表重命名
```

其中最常用的INPLACE方式，在上述常见的三种需求中依然需要rebuild table，开销比较大，对线上业务依然不够平滑，MDL锁有时难以接受。

## 2．pt-online-schema-change简介

pt-online-schema-change是percona公司开发的一个工具，在percona-toolkit包里面可以找到这个功能，它可以在线修改表结构。相对于原生的MySQL Online DDL，这款开原工具虽然有部分使用限制，但是对线上业务更加**平滑可控**，我们可以通过工具自带的通过一系列参数来定制最合适的DDL操作，使影响减少到最小。

## 3.pt-online-schema-change原理

pt-online-schema-change由perl脚本编写，实现原理主要是通过旧表上的3个**触发器**实现，大致流程图如下：

![1](https://i.postimg.cc/SN6FkLyW/1.png)

### 3.1 三种触发器的内容和具体作用分析

Creating triggers...这个步骤在拷贝旧表数据之前，这是pt-OSM能保证更改期间DML操作，即DDL期间数据一致性的关键，其实现原理非常精妙，部分定义如下：

```HTML
--旧表上的插入（insert）操作
Trigger: pt_osc_test_oil_card_transaction_record_ins
Event: INSERT
Table: oil_card_transaction_record
Statement: REPLACE INTO `test`.`_oil_card_transaction_record_new` (`col1`,…,`colN`) VALUES (NEW.`col1`,…,NEW.`colN`)
Timing: AFTER
```

分析：NEW在这里指老表上的新增内容，即DDL期间insert的内容，区别于OLD--老表上的已有内容，即DDL之前已经有的内容

通过在老表上insert操作后触发的replace into操作，在新表上复制老表上的insert操作，因为映射老表的操作和copy老表的操作时同时进行的，所以可能会出现新表已经拷贝完成，但是trigger再一次触发insert的操作，replace into很好的解决了这个问题，即如果新表存在该记录，则删除后插入，如果不存在，则直接插入。

```HTML
--旧表上的删除（delete）操作
Trigger: pt_osc_test_oil_card_transaction_record_del
Event: DELETE
Table: oil_card_transaction_record
Statement: DELETE IGNORE FROM `test`.`_oil_card_transaction_record_new` WHERE `test`.`_oil_card_transaction_record_new`.`id` <=> OLD.`id`
Timing: AFTER
```

分析：同理，这里的OLD.id指老表上已有内容里面的id（delete一定是删除老表”现在状态“下的某记录，无论这些记录是在DDL期间增加的还是之前），ignore参数表示将忽略MySQL的所有报错，因为有可能还没有copy到被删除的老表上的记录，老表上的记录就被删除了，这时新表再次执行这个删除操作会报该记录不存在。这个触发器将在老表上的delete操作执行之后，在新表上映射到id相同的记录并复制删除操作。

```HTML
--旧表上的更新（update）操作
Trigger: pt_osc_test_oil_card_transaction_record_upd
Event: UPDATE
Table: oil_card_transaction_record
Statement: BEGIN 
DELETE IGNORE FROM `test`.`_oil_card_transaction_record_new` 
WHERE !(OLD.`id` <=> NEW.`id`) 
AND 
`test`.`_oil_card_transaction_record_new`.`id` <=> OLD.`id`;
REPLACE INTO `test`.`_oil_card_transaction_record_new` (`col1`,…,`colN`) VALUES (NEW.`col1`,…,NEW.`colN`);
END
Timing: AFTER
```

分析：在3.0.2版本之前（最新版本是3.1.0），pt-online-schema-change的update触发器是没有最开始那句delete操作的，这样**会在原表update操作更新了主键时，带来冗余的脏数据**，比如，原表中的id为N的记录的主键（id）被更改了，在主键唯一性的约束下，**这个值一定是整个原表中所有id都不同的值**，假设为M；因为update触发器是replace into的操作，当映射操作到这个更新操作时，replace into发现新表上没有id=M的记录存在，因此直接插入，于是，新表上除了没映射update操作时的id=N的记录，还有一条id=M的记录，此时，**id=N的记录就变成了多余的脏数据**。

我们再来看看3.0.2后，delete语句的where条件，
```HTML
条件1：!(OLD.`id` <=> NEW.`id`)
```
之前的分析中提到OLD和NEW是对于老表在DDL之前和期间的区别，那么，当两者id相同时，说明DDL期间的更新操作中，**没有涉及到记录的主键修改**，如果没涉及，replace into就可以正常work，不需要delete，因此条件1是不为常规修改，即不为没有修改主键的update操作；

```HTML
条件2：`test`.`_oil_card_transaction_record_new`.`id` <=> OLD.`id`
```

既然满足条件1，那么这次更新一定修改了主键的值，所以这里让新表记录的id与DDL更改前记录的id相匹配，并删除，这样在后续replace into后，修改了主键值的记录继续插入，而**被修改主键值的被更新的记录就没有了**，不会产生冗余的脏数据。

>这几个神奇的replace into和delete ignore巧妙地实现了MySQL原生DDL中row_log的功能，how incredible！

## 4. pt-online-schema-change使用条件和安全性

### 4.1 使用条件（限制）

**① 原表上不能有触发器存在**

pt-osc会在原表上创建3个触发器，而一个表上不能同时有2个相同类型的触发器,为了通用可行，直接禁止原表拥有触发器。可以重写原表触发器的定义，规避冲突，最后再将原表触发器定义应用到新表。

**② 原表上需要有主键或者唯一索引**

因为会在原表上创建触发器保证新表是最新的，有主键同步到新表会更快

**③ 不允许主从中有复制过滤**

如果检测到复制过滤（ignore-db，do-db等），pt-online-schema-change会拒绝操作，除非指定执行参数--[no]check-replication-filters

**④不允许原表有外键约束**

假设 t1 是要修改的表，t2 有外键依赖于 t1，t1_new 是 alter t1 产生的新临时表。
这里的外键不是看t1上是否存在外键，而是作为子表的 t2。主要问题在 rename t1 时，t1“不存在”导致t2的外键认为参考失败，不允许rename。

pt-osc提供--alter-foreign-keys-method选项来决定怎么处理这种情况：

**方法一：rebuild_constraints**，优先采用这种方式

它先通过 alter table t2 drop fk1,add fk1 重建外键参考，指向新表
再 rename t1 t1_old, t1_new t1 ，交换表名，不影响客户端
删除旧表 t1_old
但如果字表t2太大，以致alter操作可能耗时过长，有可能会强制选择 drop_swap。

**方法二：drop_swap**，

禁用t2表外键约束检查 FOREIGN_KEY_CHECKS=0
然后 drop t1 原表
再 rename t1_new t1
这种方式速度更快，也不会阻塞请求。但有风险，第一，drop表的瞬间到rename过程，原表t1是不存在的，遇到请求会报错；第二，如果因为bug或某种原因，旧表已删，新表rename失败，那就太晚了，但这种情况很少见。

**⑤ Alter期间磁盘空间占用较大**

在做DDL期间，pt-OSC会占用该表**一倍**的磁盘空间（因为copy和更新新表），如果在
基于行binlog_format=row的复制模式下，还会写大量binlog。在DDL执行完毕后，旧表会被删除，但是期间产生的binlog会保留。

### 4.2 安全性和相关参数

**①--max-load**

默认为Threads_running=25
每个chunk拷贝完后，会检查SHOW GLOBAL STATUS的内容，检查指标是否超过了指定的阈值。
如果超过，则先暂停。
这里可以用逗号分隔，指定多个条件，
每个条件格式： status指标=MAX_VALUE 或者 status指标:MAX_VALUE。
如果不指定MAX_VALUE，那么工具会设置其为当前值的120%。
分析：因为拷贝行有可能会给部分行上锁，Threads_running 是判断当前数据库负载的绝佳指标。MySQL的连接池中，该参数代表处于**活跃状态的连接数**，很大程度上直接代表数据库的繁忙情况

**②--max-lag**

默认1s
每个chunk拷贝完成后，会查看所有复制Slave的延迟情况（Seconds_Behind_Master）。要是延迟大于该值，则暂停复制数据，**直到所有从的滞后小于这个值**。
--check-interval配合使用，指定出现从库滞后超过 max-lag，则该工具将睡眠多长时间，默认1s，再检查。如--max-lag=5 --check-interval=2。
另外，如果从库被停止，将会永远等待，直到从开始同步，并且延迟小于该值。
分析：该参数是保证复制环境下，从服务器影响也被尽可能减小。

**③--critical-load**

默认为Threads_running=50
用法基本与--max-load类似，如果不指定MAX_VALUE，那么工具会这只其为当前值的200%。
如果超过指定值，则工具直接退出，而不是暂停。
分析：设置上限，平稳执行的保险丝。

**④--set-vars**

设置MySQL变量，多个用逗号分割。
使用pt-osc进行ddl要开一个session去操作，set-vars可以在执行alter之前设定这些变量，
默认会设置

```html
--set-vars "wait_timeout=10000,innodb_lock_wait_timeout=1,lock_wait_timeout=60"。
```
分析：因为使用pt-osc之后**ddl的速度会变慢**，所以预计2.5h之后还不能改完，需要改大参数wait_timeout；
innodb_lock_wait_timeout即事务在等待**行锁**超时放弃前，最多等待的时间，依服务器设置而定，这里默认的1秒会导致频繁的异常处理消耗，不合理，可以适当增大；
lock_wait_timeout即获取到MDL锁之前，最多等待的时间，可以认为是其他事务等待DDL操作的最长时间，这里因为是online DDL，支持并发的DML操作，因此基本不会出现等待MDL锁超时的情况。

**⑤--chunk-time**

默认0.5s，即拷贝数据行的时候，为了尽量保证0.5s内拷完一个chunk，工具会动态调整chunk-size的大小，以适应服务器性能的变化。
也可以通过另外一个选项--chunk-size禁止动态调整，即每次固定拷贝 1k 行，如果指定则默认1000行，且比 chunk-time 优先生效

**⑥--[no]version-check**

默认yes，推荐--no-version-check不检查Percona Toolkit, MySQL以及其他程序的最新版本

## 5. 小结

**OSC的局限：**

通过前面的分析我们可以看到，pt-OSC在使用上除了对原表本身有一定限制外，对于系统的磁盘使用和整个DDL操作消耗的时间是非常大的，但这也是使用该工具的初衷，即为了更加平稳的执行DDL操作，只不过这里的空间换取时间变成了空间和时间换取稳定性。

**适合的使用场景：**

和5.6开始的MySQL原生DDL相比，
online ddl在必须copy（rebuild）table时成本较高，不宜采用（如添加/删除列，更改列属性，更改列顺序等）

pt-osc工具在存在触发器时，不适用

修改索引、外键、列名时，优先采用online ddl，并指定 ALGORITHM=INPLACE

其它情况使用pt-osc，虽然存在copy data

pt-osc比online ddl要慢一倍左右，因为它是根据负载调整的

无论哪种方式都选择的业务低峰期执行

特殊情况需要利用主从特性，先alter从库，主备切换，再改原主库

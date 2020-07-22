---
layout:     post
title:      MySQL next-key锁小结
subtitle:  	
date:       2020-03-09
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - gap lock
    - next-key lock
---

##1.MySQL中的行锁，间隙和间隙锁，next-key锁是什么

###1.1 行锁

对表中的记录加锁，叫做记录锁（Record lock），简称行锁

###1.2 间隙
字段值在查询条件范围中，但不存在的记录叫做间隙（Gap）
比如，查询条件where id between 1 and 6,id=1,3,6都有记录，而id=2,4,5在查询条件范围中却不存在记录，这些在查询条件范围中却不存在的记录就是"间隙"

###1.3 间隙锁
当我们在查询时使用了范围条件/相等值，并请求了排他锁（select ... for update），
InnoDB不仅会给符合条件的已有数据记录的索引项加锁，还会对"间隙"加锁，这种锁机制就是所谓的间隙锁（GAP LOCK）

###1.4 Next-Key锁
间隙锁和行锁合称Next-Key锁，
InnoDB对于行的查询都是采用了Next-Key Lock的算法，锁定的不是单个值，而是一个范围（GAP）

###1.5 Next-Key锁的范围判定
将记录以检索条件的字段值以正序排序，
根据检索条件向上寻找最靠近检索条件的记录值A，作为左区间，
向下寻找最靠近检索条件的记录值B作为右区间，即锁定的间隙为（A，B）

##2.MySQL使用next-key锁的条件

①事务隔离级别为RR
②检索条件必须有索引，且不含唯一属性（主键/唯一索引）
③如果没有索引，innodb会锁住整张表
④如果含唯一属性，Next-Key Lock 会进行优化，将其降级为Record Lock，即仅锁住索引本身，不是范围
⑤如果通过主键或唯一索引锁定了不存在的值，也会产生Next-Key Lock

##3.MySQL使用next-key锁的作用

①解决幻读

| 时间        | 事务A   |  事务B  |
| :--------:   | :-----:  | :----:  |
| T1      | select count(1) from t1 where id > 1; |       |
| T2        |      |   insert into t1 values(3,xx,yy);   | 
| T3        |        |  commit; |
| T4        |   select count(1) from t1 where id > 1;    |    |
| T5        |   commit;  |    |  |

id=3的记录一开始是不存在的
如果没有间隙锁，事务A在T1和T4读到的结果数是不一样的，有了间隙锁，事务B必须等到A提交才能插入间隙，
读的就是一样的了

②防止数据误删/改

| 时间        | 事务A   |  事务B  |
| :--------:   | :-----:  | :----:  |
| T1      | delete from t1 where id < 4; |       |
| T2        |      |   insert into t1 values(2,XX,YY);   | 
| T3        |        |  commit; |
| T4        |   commit;    |    | |

如果没有间隙锁，那么事务B在T3提交插入的值在A于T4提交后就被删除了，这对于业务的一些场景是无法接受的，
加了间隙锁之后，锁定了整个id小于4的间隙中的记录，
insert语句要等待事务A执行完之后释放锁，避免了这种情况

##4.例子+查询排序问题分析

###4.1 新建测试表

```html
create table gap_lock(
`id` tinyint not null auto_increment,
`number` tinyint not null,
primary key(`id`),
key `idx_number` (`number`)
)engine=innodb, default charset=utf8mb4;

alter table gap_lock add index idx_gap_lock_number(number);
```

###4.2 几个测试例子

Session1:
![1](https://postimg.cc/B89Csgj0)

Session2：
![1](https://postimg.cc/QV4kVsFS)

说明：
where条件指定了number=4，则此例中间隙锁的范围为
![1](https://postimg.cc/34LpyCxW)

记录（2,4）在记录（1,2）和（3,4）之间，因此阻塞
记录（2,2）在记录（1,2）和（3,4）之间，因此阻塞
记录（11,4）在记录（3,4）和（6,5）之间，因此阻塞
记录（5,5）在记录（3,4）和（6,5）之间，因此阻塞
记录（7,5）在记录（6,5）和（8,5）之间，因此执行成功

Session1：
![1](https://postimg.cc/TyfWCHyp)

Session2：
![1](https://postimg.cc/TKXy3HJC)

说明: 
where条件指定了number=5，则此例中间隙锁的范围为
![1](https://postimg.cc/GTy2ckBW)

记录(9,12)在记录（13,11）之后，因此执行成功
记录(12,11)在记录（10，5）和（13,11）之间，因此阻塞
记录（1,5）在记录（3,4）和（6,5）之间，因此阻塞
记录（11,11）在记录（10,5）和（13,11）之间，因此阻塞
记录（2,4）在记录（1,2）和（3,4）之间，因此执行成功
记录（4,4）在记录（3,4）和（6,5）之间，因此阻塞

###4.3 MySQL查询结果默认排序

这里有必要说明一下MySQL查询结果在没有使用order by，over partition by等的默认排序结果，

**结论是根据explain使用的key来排序**

如果是全表扫描（all），则为主键排序（这也是为什么我们看到select *的结果多为按自增主键列排序）
同理，在上述例子中的update，insert语句，走的哪个key，就会以key所在的列为第一排序顺序，如果该列同值，则根据主键再次排序，最后插入表中

##5.小结

MySQL通过next-key锁机制保证不会发生幻读，MVCC的实现中也使用了此机制


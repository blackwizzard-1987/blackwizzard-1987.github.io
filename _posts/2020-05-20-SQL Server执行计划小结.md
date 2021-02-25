---
layout:     post
title:      SQL Server执行计划小结
subtitle:  	
date:       2020-05-20
author:     RC
header-img: 
catalog: true
tags:
    - SQL Server
    - 执行计划
    - 优化器提示
---

执行计划顺序：从右向左

## 1.单表查询

- table scan ：全表扫描 = All

- (non)clustered index scan: (非)聚集索引扫描，扫描整个(非)聚集索引 = index

- (non)clustered index seek：(非)聚集索引查找，扫描聚集索引中特定范围的行 = range

- index seek + Key Lookup：二级索引扫描找到所在行，之后回表拿其他字段，学名书签查找 = ref

> 当基本表为堆表，则key变为RID Lookup; 当返回行数较多时，退化为索引全表扫描

- Hash Aggregate：哈希匹配(散列聚合) ，出现在含有group by的语句中，表较大时选择，较小时为sort

> sort操作是占用内存的操作，当内存不足时还会去占用tempdb

- Stream Aggregate: 流聚合，所有的聚合函数(如COUNT(),MAX())都会有流聚合的出现，但是其不会消耗IO，只消耗CPU

- Compute Scalar: 计算标量，除MIN和MAX函数之外的聚合函数都要求流聚合操作后面跟一个计算标量

- sort: 排序，一些结果集本身已经有序

## 2.多表查询

- Nested Loops： 块/索引嵌套循环，外部输入=驱动表，内部查询=被驱动表，一般驱动表较小时选择; 计划图中，上面的为驱动表，下面的为被驱动表

- Merge Join：合并连接，两张表均只扫描一次，要求双方数据有序，且on条件为=

- Hash Join： 哈希连接/散列连接，适用于两张表都较大的场景，通过选取较小表生成内存中的hash table，然后用较大表进行探测probe，找到匹配的行

> Hash Table：通过hashing处理，把数据以key/value的形式存储在表格中，在数据库中它被放在tempdb中; 通过Join Key在内存中建立

- 并行：多个表连接时，SQL Server可能会允许查询并行

## 3.optimizer hint

- 改变连接方式：语句最后OPTION(Hash/Loop/Merge Join)

- 改变索引：Select CluName1,CluName2 from Table with(index=IndexName) = force index(idx_XX)
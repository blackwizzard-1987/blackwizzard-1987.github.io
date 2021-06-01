---
layout:     post
title:      MySQL ONLY_FULL_GROUP_BY约束失效的问题
subtitle:  	
date:       2020-06-13
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - SQL_MODE
    - SQL 标准
---


## 问题描述

慢查询监控程序在线上的MySQL报表库偶然抓到了一个"神奇"的SQL，内容如下：

```html
SELECT
	c.`name`,
	NOW(),
	COUNT( 1 ) '车辆数'
FROM
	`orderoperator` o
	LEFT JOIN `carrepairshop` c ON o.`carRepairShopId` = c.`shopId`
WHERE
	o.`STATUS` IN ( 'L', 'P', 'Q' )
	AND O.`coopId` = 1
	AND c.`cooperationId` = 0
GROUP BY
	O.`carRepairShopId`;
```

从语法上来看，这个SQL有两个很明显的问题：

- left join 中的右表字段在where条件中出现， left join退化为inner join

- group by中的字段与select中的字段不一致

第一点是一个常见的错误不再赘述

第二点，我们知道，GROUP BY语法用于结合聚合函数，根据一个或多个列对分析结果进行分组。而在标准SQL语句中，如果我们使用了GROUP BY语法，则在执行SELECT语句时，**只能选择已被分组（GROUP BY）的列或者对任意列进行聚合计算的聚合函数，不允许选择未被分组（GROUP BY）的列。**

显然这个SQL是不满足这个条件的，但是它执行并且成功了。

## 问题分析

首先我们排除sql_mode的参数设置问题，5.7版本默认开启了'ONLY_FULL_GROUP_BY'，这里我们也确认了报表库是开启了这个参数的。

经过尝试，发现该SQL中的group by的列，只有在为on的条件字段（2个）以及本身select出现的字段时，才不会报错。

那么问题就很明显了，on条件的字段肯定有一定的特殊性。

本例中驱动表orderoperator的carRepairShopId字段定义如下：

```html
`carRepairShopId` int(11) DEFAULT NULL
KEY `index_orderoperator_shopId_competeTime_status` (`carRepairShopId`,`completeDateTime`,`STATUS`),
```

是一个普通的关联字段，上面有一个普通的复合索引

被驱动表carrepairshop的shopId字段定义如下：

```html
`shopId` int(11) NOT NULL AUTO_INCREMENT
PRIMARY KEY (`shopId`)
```

可以看到是这张表的主键（非空且唯一）

这里似乎问题已经得到答案了

我们看下MySQL官方文档的解释：

![1](https://i.postimg.cc/BZKCgxfC/1.png)

这里面有一句意味深长的话

```html
refer to nonaggregated columns that are neither named in the GROUP BY clause nor are functionally dependent on (uniquely determined by) GROUP BY columns
```

**意思是如果select的字段没有出现在group by的字段中，但这些字段可以被group by的字段唯一确定( functionally dependent on = uniquely determined by )，那么即使开启了ONLY_FULL_GROUP_BY，也是合法的**

这是什么意思呢，我们看下group by进行聚合时到底干了什么：

那就是按group by的字段进行了分组，然后select出每个组中对应的字段/聚合函数的结果

比如，将group by 换成一个普通的字段c.`address`：

```html
c.name  c.address
1					111
2					111
3				    111
4					222
```

此时，如果按address进行分组，那么c.name = 1-3的为一组，当查询这一组的c.name时，根本无法确定结果，因此语法错误

这种情况也是ONLY_FULL_GROUP_BY开启时主要避免的一种情况

而对于 o.`carRepairShopId`，因为跟它join的字段 c.`shopId`是右表的主键，带有**非空且唯一**的属性，因此，每个符合条件的o.`carRepairShopId`也必然是**非空且唯一**的

因此，**o.`carRepairShopId`在分组时，不可能出现重复的值，因此它可以唯一确定select中的字段c.`name`**,不受5.7.5以上版本中ONLY_FULL_GROUP_BY的限制：

```html
c.name  o.carRepairShopId
1				111
2				222
3				333
4				444
```

那么如果join的字段属性唯一但是可以为空呢

> 与其他数据库系统不同，MySQL将NULL值视为不同的值。所以，可以在唯一索引中包含很多的空值。但这样做违背了唯一索引的初衷，因此唯一性的约束应该使用not null

显然是不行的，因为字段唯一但可以为空会出现N个为null的值的情况，这时按照null分组，也会出现无法确定select字段的值的情况，即无法唯一确定：

```html
c.name  o.`carRepairShopId`
1				111
2				222
3				333
4				444
5				null
6				null
7				null
```

而经过测试，在SQL Server(2017)中，无论join的字段是否唯一，都会报错

```html
is invalid in the select list because it is not contained in either an aggregate function or the GROUP BY clause.
```

那么为什么5.7.5以上的版本(本例中为5.7.19)会允许这种group by呢

答案是不同版本的**SQL的标准不一样**

我们看下MySQL官方文档的解释:

![2](https://i.postimg.cc/c1PdqGjS/2.png)

即5.7.5之前使用的是SQL-92标准，之后使用了SQL: 1999标准，因此容许了满足唯一确定这一条件的group by的执行，即使它们'看上去'	并不符合标准语法

> 冷知识：蓝色巨人IBM对关系数据库以及SQL语言的形成和规范化产生了重大的影响，第一个版本的SQL标准SQL86就是基于System R的手册而来的。
对SQL标准影响最大的机构自然是那些著名的数据库产商，而具体的制订者则是一些非营利机构，例如国际标准化组织ISO、美国国家标准委员会ANSI等。
目前最新的SQL标准是SQL: 2016

## 结论

当MySQL版本大于5.7.5时，如果select的字段没有出现在group by的字段中，但这些字段可以被group by的字段唯一确定，那么即使开启了ONLY_FULL_GROUP_BY，也是合法的



---
layout:     post
title:      SQL Server统计信息理解
subtitle:  	
date:       2020-05-01
author:     RC
header-img: 
catalog: true
tags:
    - SQL Server
    - 统计信息概念
    - 统计信息维护
---

## 1.什么是统计信息

SQL Server查询优化器**使用统计信息来评估表或索引视图的一个或多个列中值的分布**，这个分布信息提供了用于创建高质量的执行计划的基础（称为基数）。更为通俗一点说，SQL Server的执行计划是基于统计信息来评估的，优化器最终会选择最优的执行计划来为数据库系统提供数据存取功能。

## 2.统计信息的作用

在所有关系型数据库系统（RDBMS）中，统计信息非常重要，SQL Server也不例外，它的准确与否直接影响到执行计划的优劣，数据库系统查询效率是否高效，是数据库系统快速响应，低延迟特性的关键。具体表现在以下几个方面：

·查询优化器需要借助统计信息来判断是否使用索引。

·查询优化器需要根据统计信息来判断是使用嵌套循环连接，合并连接还是哈希连接。

·查询优化器根据表统计信息来找出最佳的执行顺序。


## 3.统计信息包含的内容

```html
通过DBCC命令：
use testDB
dbcc SHOW_STATISTICS('dbo.OrderInfo','_WA_Sys_00000002_267ABA7A')
```

![1](https://i.postimg.cc/bJ3364sS/1.png)

从这张图中可以看到：

```html
统计信息头部
Name：统计信息的名字
Updated：更新时间
Rows：包含行数
Rows Sampled：采样行数
Steps：数据采样步长
Density：数据密度
Average key length：平均长度
String Index：为string的like时，统计估计行数
Filter Expression：过滤表达式
Unfiltered Rows：未过滤行数
```

```html
直方图
RANGE_HI_KEY：采样步长最大值
RANGE_ROWS：步长包含行数
EQ_ROWS：等于采样步长最大的行数
DISTINCT_RANGE_ROWS：
步长范围内唯一值的个数
AVG_RANGE_ROWS：步长范围内行数唯一性平均值
```

```html
密度向量
All density ：统计信息密度
Average Length：平均长度
Columns：统计信息包含的列
```

## 4.查看统计信息的设置情况

关于统计信息的设置，共有4个重要选项

```html
Auto Create Statistics：SQL Server是否自动创建统计信息，默认开启。
Auto Update Statistics：SQL Server是否自动更新统计信息，默认开启。
Auto Update Statistics Asynchronously：SQL Server是否采用异步方式更新统计信息，默认关闭。
Auto Create Incremental Statistics：SQL Server是否自动创建增量统计信息，这个选项是SQL Server 2014以来新增选项，默认关闭
```

通过sys.databases查看某个数据库的统计信息当前设置情况：

![1](https://i.postimg.cc/2jgXPR0n/2.png)

通过SSMS查看某个数据库的统计信息当前设置情况：

右键数据库->属性->选项

![1](https://i.postimg.cc/Zn6PGgqL/4.png)

## 5.统计信息对查询的影响

为了更清楚的了解统计信息是如何影响查询的，我们在testDB下创建一张测试表，并插入1W条数据作为测试：

```html
USE testDB
GO
IF OBJECT_ID('dbo.TestStats', 'U') IS NOT NULL
BEGIN
	TRUNCATE TABLE dbo. TestStats
	DROP TABLE dbo.TestStats
END
GO

CREATE TABLE dbo.TestStats
(
	RowID INT IDENTITY(1,1) NOT NULL
	,refID INT NOT NULL
	,anotherID INT NOT NULL
	,CONSTRAINT PK_TestStats PRIMARY KEY (RowID)
);

USE testDB
GO

--不返回受SQL影响的行数的信息
SET NOCOUNT ON
DECLARE
	@do int = 0
	,@loop int = 10000
;
WHILE @do < @loop
BEGIN
	IF @do < 100
		INSERT INTO dbo.TestStats(refID,anotherID) VALUES(@do, @do);
	ELSE
		INSERT INTO dbo.TestStats(refID,anotherID) VALUES(200, 200);

	SET @do = @do + 1;
END;

```

### 5.1 无统计信息的执行计划

为了排除SQL SERVER在执行计划评估阶段自动创建统计信息带来的影响，先关闭AUTO_CREATE_STATISTICS选项

```html
ALTER DATABASE testDB SET AUTO_CREATE_STATISTICS OFF;
```

然后打开SSMS的实际执行计划![1](https://i.postimg.cc/63f5FfXv/6.png)，执行下面的SQL

```html
USE testDB
SELECT * FROM dbo.TestStats WITH(NOLOCK) WHERE anotherID = 100;
```

执行计划如下：

![1](https://i.postimg.cc/wjRx9pzH/7.png)

从实际的执行计划来看，实际满足条件的记录数没有，即Actual Numbers of Rows为0，而预估满足条件的记录数Estimated Numbers of Rows为100条，差异较大，并且存在统计信息缺失的警告。这个差异足以导致SQL Server优化器对执行计划评估不准确，从而选择了次优的执行计划，最终影响数据库查询效率。

### 5.2 有统计信息的执行计划

先手动创建基于查询列的统计信息

```html
USE testDB
CREATE STATISTICS st_anotherID ON dbo.TestStats(anotherID)
```

为排除执行计划缓存对测试的影响，先清空执行计划缓存，再重新执行查询

```html
--清除执行计划缓存
DBCC FREEPROCCACHE
USE testDB
SELECT * FROM dbo.TestStats WITH(NOLOCK) WHERE anotherID = 100;
USE master
--将设置还原为自动创建统计信息 
ALTER DATABASE testDB SET AUTO_CREATE_STATISTICS ON;
```

实际执行计划如下：

![1](https://i.postimg.cc/j2C0vHdK/8.png)

可以看到，和之前相比，统计信息缺失的警告消失了，预估满足条件的行数Estimated Numbers of Rows为1行和实际满足条件的行数Actual Numbers of Rows为0行，非常接近了。说明统计信息的存在为优化器提供了正确的数据分布图，给优化器选择最优路径带来了积极的影响。

## 6.创建和维护统计信息

### 6.1 自动创建

当我们执行一个精确查询语句时，查询优化器会判断谓词中使用的到列，统计信息是否可用，如果不可用则会单独对每列创建统计信息。这些统计信息对创建一个高效的执行计划非常必要。

```html
USE testDB
SELECT * FROM dbo.TestStats WITH(NOLOCK) WHERE refID = 100;
```

当执行了精确查询以后，发现多了一个名为_WA_Sys_00000002_6E01572D的统计信息，这个统计信息就是SQL Server自动为我们创建的，因为我们开启了自动创建统计信息的选项。

![1](https://i.postimg.cc/yYM4XSq4/9.png)

### 6.2 创建索引时自动创建

在我们创建测试表时，创建了一个主键，主键是一个特殊的索引，SQL Server系统会为每一个索引自动创建一个统计信息，可以通过下面的SQL查看:

```html
USE testDB
SELECT  
	statistics_name = st.name
	,table_name = OBJECT_NAME(st.object_id)
	,column_name = COL_NAME(stc.object_id, stc.column_id)
FROM    sys.stats AS st WITH(NOLOCK) 
        INNER JOIN sys.stats_columns AS stc WITH(NOLOCK)
			ON st.object_id = stc.object_id  
			AND st.stats_id = stc.stats_id 
WHERE st.object_id = object_id('dbo.TestStats', 'U')
```

![1](https://i.postimg.cc/Gmv0MhrB/10.png)

由此可见，**一张表的统计信息个数与它被执行的精确查询的列数目和索引数目成正比**


### 6.3 手动创建

当实际执行计划有统计信息缺失的警告（Columns with no statistics）时，需要手动在相应字段上创建统计信息

```html
USE testDB
CREATE STATISTICS st_anotherID ON dbo.TestStats(anotherID)
```

以及下列情况：

①查询执行时间很长

②在升序或降序键列上发生插入操作

③在维护操作后

### 6.4 更新统计信息

#### 6.4.1 更新的时机

① 查询执行缓慢，或者查询语句突然执行缓慢

② 当大量数据更新（INSERT/DELETE/UPDATE）到升序或者降序的列时，更新统计信息。因为在这种情况下，统计信息直方图可能没有及时更新。

③ 强烈建议在除索引维护（当你重建、整理碎片或者重组索引时，数据分布不会改变）外的维护工作之后更新统计信息。

④ 如果数据库的数据更改频繁，建议最低限度每天更新一次统计信息。数据仓库可以适当降低更新统计信息的频率。

⑤当执行计划出现统计信息缺失警告时，需要手动建立统计信息，在上面的手动创建小节就属于这种情况。

#### 6.4.2 找到过期的统计信息

过期的统计信息会引起大量的查询性能问题，没有及时更新统计信息常见的影响是优化器选择了次优的执行计划，然后导致性能下降。有时候，**过期的统计信息可能比没有统计信息更加糟糕**。为了避免这种情况，我们可以使用系统视图sys.stats和系统函数STATS_DATE来获取到统计信息最后更新的时间。假如我们定义超过7天未更新的统计信息算过期的话，那么查找过期的统计信息语句如下：

```html
USE 
DECLARE
	@day_before int = 7
SELECT 
	Object_name = OBJECT_NAME(object_id)
	,Stats_Name = [name]
	,Stats_Last_Updated = STATS_DATE([object_id], [stats_id])
FROM sys.stats WITH(NOLOCK)
WHERE STATS_DATE([object_id], [stats_id]) <= DATEADD(day, -@day_before, getdate());
```

#### 6.4.3 手动更新统计信息

```html
索引级别更新
UPDATE STATISTICS dbo.DeviceType IX_DeviceType_Name;
--dbcc show_statistics('DeviceType','IX_DeviceType_Name')
```

```html
表级别更新
UPDATE STATISTICS dbo.TestStats WITH FULLSCAN;
```

```html
库级别更新
USE testDB
EXEC sys.sp_updatestats
```

```html
实例级别更新
--通过sys.sp_msforeachdb遍历所有数据库
USE master
go
DECLARE
	@sql NVARCHAR(MAX)
SET
	@sql = N'
USE [?]
IF ''?'' NOT IN(''master'', ''model'', ''msdb'', ''tempdb'', ''distribution'') 
BEGIN
--通过RAISERROR打印提示信息
	RAISERROR(N''--------------------------------------------------------------
Search on database: ?'', 10, 1) WITH NOWAIT
	EXEC sys.sp_updatestats
END
'
--指定的占位符号为？，即形式参数
EXEC SYS.SP_MSFOREACHDB @sql,@replacechar=N'?'
```

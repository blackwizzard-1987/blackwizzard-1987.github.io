---
layout:     post
title:      MySQL慢日志相关参数和pt-query-digest&tcpdump
subtitle:  	
date:       2020-05-03
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - 慢日志
    - pt-query-digest
---

## 1.MySQL慢日志相关参数

```html
系统变量：slow_query_log
默认值：OFF
意义：是否开启慢查询日志
说明：开启慢日志是为了调优需要，对数据库性能有一定影响
```

```html
系统变量：slow_query_log_file
默认值：服务器名-slow.log
意义：慢日志文件路径
说明：该参数与log_output相关，建议将慢日志记录到文件中，如果不指定绝对路径，则默认保存在datadir下
```

```html
系统变量：log_output
默认值：FILE
意义：=FILE表示将日志存入文件，=TABLE表示将日志存入数据库表mysql.slow_log
说明：日志记录到系统的专用日志表中，要比记录到文件耗费更多的系统资源，建议优先记录到文件
```

```html
系统变量：long_query_time
默认值：10
意义：慢查询记录的条件①，即查询时间的多少
说明：支持毫秒，不包括这个值；当一个SQL的执行时间大于该值时，才有可能被记入日志，执行时间不包括锁等待时间（lock time），但是记录之后会记录查询时间（query time），查询时间=执行时间+锁等待时间
```

```html
系统变量：log_queries_not_using_indexes
默认值：OFF
意义：慢查询记录的条件②，将没有使用索引的SQL记录到慢查询日志
说明：该参数最好配合log_throttle_queries_not_using_indexes和min_examined_row_limit参数使用，否则会丢掉一部分“真的”没使用索引的慢查询记录
```

```html
系统变量：log_throttle_queries_not_using_indexes
默认值：0
意义：每分钟内最多记录到慢查询日志的不使用索引的SQL数
说明：该参数由窗口控制，最好配合min_examined_row_limit参数使用，否则会丢掉一部分“真的”没使用索引的慢查询记录
```

```html
系统变量：min_examined_row_limit
默认值：0
意义：慢查询记录的条件③，将扫描行数大于此值的查询记录到慢查询日志中
说明：条件3与条件1和2为and关系，即必须满足；如果开启log_queries_not_using_indexes，不建议设为0，尽量设置一定值屏蔽掉正常的查询
```

```html
系统变量：log_slow_admin_statements
默认值：OFF
意义：是否记录管理类的命令到慢日志
说明：指ALTER TABLE,ANALYZE TABLE, CHECK TABLE, CREATE INDEX, DROP INDEX, OPTIMIZE TABLE,REPAIR TABLE等命令
```

```html
系统变量：log_slow_slave_statements
默认值：OFF
意义：在从库上设置，是否在回放过程中记录慢查询日志
说明：如果binlog格式是row，则即使开启了该参数，也不会记录相关SQL
```

### 1.1 log_queries_not_using_indexes相关参数详细说明

a.log_throttle_queries_not_using_indexes的原理：

由于数据库实例中可能有较多不走索引的SQL语句，若开启log_queries_not_using_indexes，则存在日志文件或表容量增长过快的风险，此时可通过设置log_throttle_queries_not_using_indexes来限制每分钟写入慢日志中的不走索引的SQL语句个数，该参数默认为0，表示不开启，也就是说不对写入SQL语句条数进行控制。启用后，系统会在第一条不走索引的查询执行后开启一个60s的窗口，在该窗口内，仅记录最多log_throttle_queries_not_using_indexes条SQL语句。超出部分将被抑制，在时间窗结束时，会打印该窗口内被抑制的慢查询条数以及这些慢查询一共花费的时间:

![1](https://i.postimg.cc/DwMzHPFy/Screenshot-1.png)

下一个统计时间窗并不是马上创建，而是在下一条不走索引的查询执行后开启。
这个参数在每次打开窗口后，只要是不走索引的SQL都会让计数+1，超过该参数的值后，后续的不走索引的SQL都会被抑制—即只记录条数和总的时间，那么，可以设想，**如果开启了该参数，且为一个较小值（10），并且不设置最小扫描行数（0），则很多真正没有使用索引的慢查询是不会被记录的**

b.几个条件的关系：

条件1：SQL执行时间超过long_query_time

条件2：SQL没有走索引log_queries_not_using_indexes

条件3：SQL扫描行数超过min_examined_row_limit

关系： （条件1 **or** 条件2）**and** 条件3

**其中，条件1和2都是单独记录，记录过程中不受其他参数影响**，这也是为什么一个窗口内不走索引的SQL非常多，比如几百条，但是实际记录的条数并不多（**被条件3筛选掉了**），
同时，也解释了为什么小于条件1的时间的SQL也会被记录到日志中（**条件3是默认值0**）

c.一个问题：
在设置了条件1，如1秒，条件2，如10，条件3，如100000后，为什么一个超过1分钟执行时间的慢查询SQL在日志中没有记录？

由这几段源码可以看出:

![1](https://i.postimg.cc/g2CW3SmR/Screenshot-2.png)

![1](https://i.postimg.cc/SKdgmRTs/Screenshot-3.png)

![1](https://i.postimg.cc/44jkD2H0/Screenshot-4.png)

很显然是参数log_throttle_queries_not_using_indexes抑制了这条SQL，即1分钟内不走索引的SQL超过了该参数的值（10），后续进入的不走索引SQL全部汇总了（被抑制），其中就包括这条“真”的慢SQL；那么，将log_throttle_queries_not_using_indexes设置为0（即不限制）时，这条SQL将被记录。

而为什么此时慢查询日志里面并没有记录10条，甚至被抑制那么多条慢查询呢？这是因为条件3筛选掉了大多数不满足扫描行数的，但是进入了条件log_queries_not_using_indexes，并且在log_throttle_queries_not_using_indexes打开的同一个窗口中的大量SQL。

因此我们可以看出，log_throttle_queries_not_using_indexes是一个**按记录的先后顺序进行筛选的条件**，即先进入的10条，无论是否满足条件3，只要没用index，就会被选出，然后再根据条件3判断是否写入慢日志。

log_throttle_queries_not_using_indexes是个很关键的参数，当这个值很小，系统未使用index的语句较多时，**设置不当会无法正常记录不走索引的慢查询**，导致慢日志功能部分失效。

d.如何解决：

1.不开启log_queries_not_using_indexes，仅靠条件1筛选

2.开启log_queries_not_using_indexes，

**将log_throttle_queries_not_using_indexes设置为一个较大的值**（保证嫌疑的SQL都能去条件3判断）

**并且将min_examined_row_limit设置为一个合适的较大值**

最终效果：

![1](https://i.postimg.cc/x8fJnjZ0/1598867136459.png)

可以看到，

开启log_queries_not_using_indexes的条件下，

改大参数log_throttle_queries_not_using_indexes为300，

min_examined_row_limit为10000，

**没有被抑制的未走索引的SQL**（即0 'index not used' warning(s)）（均被检测）

**并且记录到了真正满足条件的慢查询**（条件1和条件3）

> 实际上在后续修改线上数据库该参数时，考虑到平均QPS（300-500），将log_throttle_queries_not_using_indexes改为了10000，
将min_examined_row_limit改为了10，几乎能涵盖所有有问题的慢查询，效果提升明显

### 1.2 轮换慢日志

```html
$ mv slowlog slowlog.1;
mysql > flush slow logs;
```
## 2.pt-query-digest的使用

### 2.1 MySQL源生慢日志的输出内容

![1](https://i.postimg.cc/1XJfQPBh/Screenshot-5.png)

可以看到源生的日志内容还是比较全面和详细的，但我们还可以利用pt-query-digest把分析结果输出到文件中，先对查询语句的条件进行参数化，然后对参数化以后的查询进行**分组统计，统计出各查询的执行时间、次数、占比等**，可以借助分析结果找出问题进行优化。

### 2.2 pt-query-digest 的分析报告解析

**第一部分：总体统计结果**

![1](https://i.postimg.cc/1RqS1yWp/15989244272753.png)

第一行：该工具执行日志分析的用户时间，系统时间，物理内存占用大小，虚拟内存占用大小

第二行：工具执行时间

第三行：运行分析工具的主机名

第四行：被分析的文件名

```html
Overall: 总共有多少条查询，上例为总共240630个查询。
Time range: 查询执行的时间范围。
unique: 唯一查询数量，即对查询条件进行参数化以后，总共有多少个不同的查询，该例为244。
total: 总计   min:最小   max: 最大  avg:平均
95%: 把所有值从小到大排列，位置位于95%的那个数，正态分布，这个数一般最具有参考价值。
median: 中位数，把所有值从小到大排列，位置位于中间那个数。
```

```html
Exec time：SQL执行时间
Lock time：锁等待时间
Rows sent：结果集返回到客户端的行数大小之和(B)
Rows examine：select语句扫描的行数大小之和(B)
Query size：查询的字符数
```

**第二部分：查询分组统计结果**

![1](https://i.postimg.cc/mD4YZLYt/Screenshot-6.png)

这部分对查询进行参数化并分组，然后对各类查询的执行情况进行分析，结果按总执行时长，从大到小排序（通过--order-by指定, 可以为max/min/avg/sum，默认为sum）

```html
Query ID：语句的ID，（去掉多余空格和文本字符，计算hash值）
Response time：响应时间，占所有响应时间的百分比
Calls: 该类查询执行的次数
R/Call：平均响应时间
V/M：每次响应时间和平均响应时间的样本方差（该值正比于数据波动程度）
Item：查询语句一部分
```

**第三部分：每一种查询的详细统计结果**

![1](https://i.postimg.cc/zDKfSw1Z/1598925709260.png)

```html
2号查询的详细统计结果，最上面的表格列出了执行次数、最大、最小、平均、95%等各项目的统计。 
Databases: 库名 
Users: 各个用户执行的次数（占比） 
Query_time distribution : 查询时间分布, 长短体现区间占比，本例中1s-10s之间查询数量是10s以上的N倍。 
Tables: 查询中涉及到的表 
Explain: 示例
```

### 2.3 pt-query-digest的常见用法

```html
分析最近12小时内的查询：
pt-query-digest --since=12h slow.log > slow_report.log
```

```html
分析指定时间范围内的查询：
pt-query-digest slow.log --since '2020-04-10 00:30:00' --until '2020-04-10 18:00:00' > slow_report.log
```

```html
分析只含有select语句的慢查询：
pt-query-digest --filter '$event->{fingerprint} =~ m/^select/i' slow.log> slow_report.log
```

```html
针对某个用户的慢查询：
pt-query-digest --filter '($event->{user} || "") =~ m/^root/i' slow.log> slow_report.log
```

```html
查询所有的全表扫描或full join的慢查询
pt-query-digest --filter '(($event->{Full_scan} || "") eq "yes") || (($event->{Full_join} || "") eq "yes")' slow.log > slow_report.log
```

## 3.tcpdump的使用

对于线上服务器，一般没有打开general log，tcpdump无疑是实时抓取MySQL query然后配合pt-query-digest进行分析的利器

```html
tcpdump -s 65535 -x -nn -q -tttt -i any -c 1000 port 3306 > mysql.tcp.txt
参数说明：
-s：snaplen表示从一个包中截取的字节数。0和65535表示包不截断，抓完整的数据包
-x：打印每个数据包包头跟数据包内容，用于分析时必须打开
-nn：不解析ip到主机名、端口号到服务名，而是直接以 ip、port的形式显示
-q：安静模式，很少打印有关协议的信息，与分析无关
-tttt：在每行打印前打印日期，作为时间统计
-i any：抓取所有网口的包，抓取 eth0等使用网卡也可以
-c：抓取N个数据包
port：端口号
```

```html
pt-query-digest --type tcpdump mysql.tcp.txt
产生的报告同第二节所述
```

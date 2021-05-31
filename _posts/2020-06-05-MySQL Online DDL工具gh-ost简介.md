---
layout:     post
title:      MySQL Online DDL工具gh-ost简介
subtitle:  	
date:       2020-06-05
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - Online DDL
    - gh-ost
---


## 1. 背景

### 1.1 基于触发器的在线修改工具的问题

pt-online-schema-change, LHM 和 oak-online-alter-table这些工具都使用同步的方式，当原表有变更操作时利用一些事务的间隙时间将这些变化同步到临时表，所有的这些工具都使用触发器来识别原表的变更操作，带来的潜在问题如下：

- 触发器是以解释型代码的方式保存的。MySQL 不会预编译这些代码。 会在每次的事务空间中被调用，它们被添加到被操作的表的每个查询行为之前的分析和解释器中,带来额外的开销

- 当主库负载上升，我们可以暂停工具的行复制操作，但无法暂停触发器的工作，触发器需要在整个操作过程中都要存在，可能会造成系统资源占用

- 触发器在原始表查询中共享相同的事务空间，可能会在极端情况下影响主库的并发写性能

### 1.2 gh-ost对比触发器类型工具的优势

- 无触发器
gh-ost 没有使用触发器。它通过分析binlog日志的形式来监听表中的数据变更。因此它的工作模式是异步的，只有当原始表的更改被提交后才会将变更同步到临时表（ghost table）

- 轻量级
因为不需要使用触发器，gh-ost 把修改表定义的负载和正常的业务负载解耦开了。**它不需要考虑被修改的表上的并发操作和竞争**等，这些在二进制日志中都被序列化了，**gh-ost 只操作临时表，完全与原始表不相干**。事实上，gh-ost 也把行拷贝的写操作与二进制日志的写操作序列化了，这样，对主库来说**只是有一条连接在顺序的向临时表中不断写入数据**，这样的行为与常见的 ETL 相当不同。

- 可暂停
gh-ost在执行过程中因为本身是读取二进制文件生成操作，因此可以随机暂停和继续copy数据和应用binlog到影子表的操作，通过标志位文件或者socat命令

- 动态调整
不同于别的DDL工具，修改配置后需要重新反复操作，gh-ost可以通过unix socket 文件来获取最新的运行参数，比如修改chunk-size，max-lag-millis，max-load等，配置后立即生效，且不需要重新运行

- 高可用
gh-ost提供测试功能，即--test-on-replica 选项，它允许你在从库上运行起修改表结构操作，在操作结束时会暂停主从复制，让两张表都处于同步、就绪状态，然后切换表、再切换回来。这样就可以让用户从容不迫地对两张表进行检查和对比
另外，gh-ost还支持**切换推迟**操作，即推迟最后新表和原表的交换操作，直到特定的文件被删除，期间它还会仍然继续同步数据，保持临时表的数据处于同步状态。


## 2. 工作原理

![1](https://i.postimg.cc/JhSgN5HJ/1.png)

```html
① 检查有没有外键和触发器
② 检查表的主键信息
③ 检查是否主库或从库，是否开启log_slave_updates，以及binlog信息
④ 检查gho和del结尾的临时表是否存在
⑤ 创建ghc结尾的表，存数据迁移的信息，以及binlog信息等
---以上校验阶段
⑥ 初始化stream的连接,添加binlog的监听
---以下迁移阶段
⑥ 创建gho结尾的临时表，执行DDL在gho结尾的临时表上
⑦ 开启事务，按照主键id把源表数据写入到gho结尾的表上，再提交，以及binlog apply
---以下cut-over阶段
⑧ lock源表，rename 源表 to 源_del表，gho表 to 源表
⑨ 清理ghc表
```

我们着重看下整个过程中比较关键的2个地方：

### 2.1 迁移数据的一致性

gh-ost 做 DDL 变更期间对原表和影子表的操作有三种：对原表的 row copy （我们用 A 操作代替），业务对原表的 DML 操作(B)，对影子表的 apply binlog(C)。而且 binlog 是基于 DML 操作产生的，因此对影子表的 apply binlog 一定在 对原表的 DML 之后，共有如下几种顺序：

![2](https://i.postimg.cc/W3ryXq0y/2.png)

通过这几种组合可以看到，数据最终是一致的，当copy结束后，只有apply binlog操作

**这里有个问题**：

B-C-A和B-A-C的模式都是建立在gh-ost自己的binlog保存/及时应用的情况下
对于数据还未copy到影子表，而原表已经进行了DML操作的情况，在gh-ost中会显示为Backlog: N/1000， **N是指二进制日志中积压的事件数**，而我目前没有看到修改次参数的地方，应该是程序写死的，那么如果原表上的DML操作非常活跃，这个backlog写满了，就**无法记录后续的DML操作转化为二进制日志，即丢失数据**

为了避免这个情况，gh-ost设置了apply binlog的优先级大于row copy

### 2.2 cut-over切换

gh-ost 的切换是**原子性切换**，基本是通过两个会话的操作来完成。

主要利用了MySQL的内部机制：

**被 lock table 阻塞之后，执行 rename 的优先级高于 DML，也即先执行 rename table ，然后执行 DML**

我们假设gh-ost 操作的会话是 c10 和 c20，其他业务的 DML 请求的会话是 c1-c9，c11-c19，c21-c29，b表是ddl更改的表，(下划线b_gho)是b表的影子表

```html
会话 c1-c9: 对b表正常执行DML操作
会话 c10 : 创建_b_del 防止提前rename 表，导致数据丢失
会话 c10 执行LOCK TABLES b WRITE, `_b_del` WRITE
此时，会话c11-c19 新进来的dml请求，但是会因为表b上有锁而等待
会话c20:设置锁等待时间并执行rename
set session lock_wait_timeout:=1
rename /* gh-ost */ table `test`.`b` to `test`.`_b_del`, `test`.`_b_gho` to `test`.`b`
c20 的操作因为c10锁表b和_b_del而等待
c21-c29 对于表 b 新进来的请求因为lock table和rename table 而等待
会话c10 通过sql 检查会话c20 在执行rename操作并且在等待mdl锁
c10 基于上个步骤的判断， 执行drop table `_b_del` , 
删除命令执行完，b表依然不能写。所有的dml请求依然都被阻塞
c10 执行UNLOCK TABLES;
此时c20的rename命令第一个被执行。
(无论 rename table 和 DML 操作谁先执行，被阻塞后 rename table 总是优先于 DML 被执行)
之后其他会话c1-c9,c11-c19,c21-c29的请求可以操作新的表b
```

<font color=red>问题1：如果cut-over过程中任一环节的失败会造成什么？</font>

```html
如果c10的create `_b_del` 失败，gh-ost 程序退出
如果c10的加锁语句失败，gh-ost 程序退出，因为表还未被锁定，dml请求可以正常进行
如果c10在c20执行rename之前出现异常
a. c10持有的锁被释放，查询c1-c9，c11-c19的请求可以立即在b执行
b. 因为`_b_del`表存在, c20的rename table b to `_b_del`会失败
c. 一些查询等待了一段时间，可能需要重试
如果c10在c20执行rename被阻塞时失败退出,与上述类似，锁释放，则c20执行rename操作依然因为b_del表存在而失败，所有请求恢复正常
如果c20异常失败，gh-ost会捕获不到rename，会话c10继续运行，释放lock，所有请求恢复正常
如果c10和c20都失败了，c10的 lock被清除，c20的rename锁被清除。c1-c9，c11-c19，c21-c29可以在b上正常执行。
```
因此可以得出结论：

对程序的影响：在cut-over期间，应用程序对表的写操作被阻止，直到交换影子表成功或直到操作失败。如果成功，则应用程序继续在新表上进行操作。如果切换失败，应用程序继续在原表上进行操作。

对复制的影响：slave 因为 binlog 文件中不会复制 lock 语句，只能应用 rename 语句进行原子操作，对复制无损。

## 3. 工作模式

**模式一：连上从库，在主库上修改**

这是 gh-ost 默认的工作模式，它会查看从库情况，找到集群的主库并且连接上去。修改操作的具体步骤是：

在主库上读写行数据；
在从库上读取二进制日志事件，将变更应用到主库上；
在从库上查看表格式、字段、主键、总行数等；
在从库上读取 gh-ost 内部事件日志（比如心跳）；
在主库上完成表切换；

**缺点**：因为此模式下的binlog是从从库读取的，可能会有主从不一致的风险

**模式二：直接在主库上修改（推荐）**

如果没有从库或者不想在从库上操作，或者处于高可用架构中（如MGR），可以直接在主库上进行修改，需要配置参数- -allow-on-master，并且主库的二进制日志格式为Row

**缺点**：所有操作都在主库上，会造成一些负担，可以通过调整负载参数来降低

**模式三：在从库上修改和测试**

这种模式会在从库上做修改。gh-ost 仍然会连上主库，但所有操作都是在从库上做的，不会对主库产生任何影响。在操作过程中，gh-ost 也会不时地暂停，以便从库的数据可以保持最新。- -migrate-on-replica 选项让 gh-ost 直接在从库上修改表。最终的切换过程也是在从库正常复制的状态下完成的。- -test-on-replica 表明操作只是为了测试目的。在进行最终的切换操作之前，复制会被停止。原始表和临时表会相互切换，再切换回来，最终相当于原始表没被动过。主从复制暂停的状态下，我们可以检查和对比这两张表中的数据。

**缺点**：模式三中的cut over会有stop slave的操作，为了方便比较切换前后的影子表和原表，这个时间可能会造成业务影响，因此不适合线上库

## 4. 环境配置和安装

```html
安装golang：
$ yum -y install golang
安装socat：
$ yum install -y socat
从 github 发布地址下载最新的 binary 包：
https://github.com/github/gh-ost/releases
解压后只有一个二进制文件gh-ost
非常的简洁，几乎没有任何依赖
```

## 5. 常用参数

```html
--chunk-size
在每次迭代中处理的行数量，即每次从原表copy到影子表的条数，默认1000
```

```html
--max-load
负载阈值，超过这个值时将暂停copy操作，应用日志依然继续，直到降到该值以下，需要自定义设置，如Threads_running=50，Threads_connected=200
```

![3](https://i.postimg.cc/DyCxQPtZ/3.png)

```html
--critical-load
严重阈值，当设置的值达到此参数时会强制退出gh-ost
```

```html
--ok-to-drop-table
是否在cut-over之后删除老表，如果不加此参数，会保留上文提到的_b_del表
```

```html
--initially-drop-ghost-table
是否在执行前删除go-ost的影子表和日志表XX_gho，XX_ghc
```

```html
--initially-drop-socket-file
是否删除上次执行时产生的socket文件
```

```html
--allow-on-master
所有操作都在主库上进行
```

```html
--dml-batch-size
gh-ost在apply binlog阶段每次事务中包含的事件数量，默认10，设为1表示不进行分组，事件按原来自己的事务应用到ghost表上
```

![4](https://i.postimg.cc/Vkp4pLsP/4.png)

```html
--postpone-cut-over-flag-file
指定的文件存在时，gh-ost的cut-over阶段将会被推迟，数据仍然在复制，直到该文件被删除（在执行开始后会自动创建）
```

```html
--nice-ratio
每次copy后的sleep时间，默认0，即不休眠，若为1，则每copy一次花费1秒，则sleep 1秒，设为0.7，则每copy花费10秒，则sleep 7
```

![5](https://i.postimg.cc/L4DDRV4T/5.png)

```html
--panic-flag-file
当指定的文件被创建时，gh-ost将会立即退出
```

```html
--verbose
输出日志
```

```html
--execute
确认执行alter&migrate表，默认为noop，不执行，仅仅做测试并退出
```



## 6. 使用测试

测试表为线上一张10W左右大小的表，导入到测试环境192.xx.xx.186，186为测试环境MGR的读写节点

```html
gh-ost \
 --ok-to-drop-table \
 --initially-drop-ghost-table \ 
 --initially-drop-socket-file \ 
 --host="192.xx.xx.186" \ 
 --port=3306 \ 
 --user="ghost" \ 
 --password="xxx" \
 --database="ghost" \ 
 --table="key_inventory" \
 --verbose \
 --alter="add column test_field varchar(256) default '111';" \
 --panic-flag-file=/tmp/ghost.panic.flag \
 --allow-on-master \ 
 --postpone-cut-over-flag-file=/tmp/wait.flag \
 --execute
 ```

日志输出：

![6](https://i.postimg.cc/GtgvDqHn/6.png)

```html
Copy: 6000/109125 5.5%; 109125指需要迁移总行数，6000指已经迁移的行数，5.5 %指迁移完成的百分比。
Applied: 0，指在二进制日志中处理的event数量。在上面的例子中，迁移表没有流量，因此没有被应用日志event。
Backlog: 0/1000，表示我们在应用二进制日志方面表现良好，在二进制日志队列中没有任何积压（Backlog）事件。
Backlog: 7/1000，当复制行时，在二进制日志中积压了一些事件，并且需要应用。
Backlog: 1000/1000，表示我们的1000个事件的缓冲区已满（程序写死的1000个事件缓冲区，低版本是100个），此时就注意binlog写入量非常大，gh-ost处理不过来event了，可能需要暂停binlog读取，需要优先应用缓冲区的事件。
streamer: binlog.000001:95531478; 表示当前已经应用到binlog文件位置
ETA: 预计完成还需要的时间
```
```

![7](https://i.postimg.cc/X7XfWSzj/7.png)

可以看到，影子表一开始就是改好表结构的，与OSC思路一致

![8](https://i.postimg.cc/cLw81sMS/8.png)

每次copy的条数与chunk size一致

加入cut-over hold的flag文件后，migrate阶段结束后会一直推迟直到flag文件删除

![9](https://i.postimg.cc/FKvk72DJ/9.png)

![10](https://i.postimg.cc/xdPJHt4p/10.png)

观察日志表的结构和内容，大小

![11](https://i.postimg.cc/k4XVyWrJ/11.png)

![12](https://i.postimg.cc/0QWzXrxp/12.png)

日志表中是一些心跳检测的内容

当copy完成进入cut over阶段时，日志表的变化

![13](https://i.postimg.cc/rsDKBcF7/13.png)

此时新增一些数据

![14](https://i.postimg.cc/Rh2N98Wh/14.png)

Change log的变化

![15](https://i.postimg.cc/440KzKWG/15.png)

![16](https://i.postimg.cc/0yRbBTgH/16.png)

变更已经成功应用到新表

删除wait flag文件，日志变化

可以看到cut-over最后阶段锁表的信息也会被打印

![17](https://i.postimg.cc/CxGzTcSM/17.png)

![18](https://i.postimg.cc/Dz50mmSt/18.png)

可以看到默认的sock文件和自动生成的wait文件

暂停操作：

![19](https://i.postimg.cc/NF2jN4dc/19.png)

![20](https://i.postimg.cc/T2BVTHMn/20.png)

动态修改限速参数：

每修改一次，都会打印最新参数

![21](https://i.postimg.cc/d0Qd5brc/21.png)

![22](https://i.postimg.cc/W49ZC5wF/22.png)

恢复操作：

![23](https://i.postimg.cc/k4BSmWTj/23.png)

这里虽然恢复了，但是我们看到go返回了一个错误

![24](https://i.postimg.cc/G2Vyh9Nb/24.png)

指mysql的查询结果没有返回值，导致无法进行下一步

源码较复杂，go和C都有，原因不明

![25](https://i.postimg.cc/KjTgKxSB/25.png)

## 7. 总结

**优点：**
能够推迟切换，动态调整负载参数，随时暂停继续，整个DDL过程可控，切换阶段安全可靠，回滚代价小，对运维人员友好

**缺点：**
因为应用日志程序写死了只有1000个事务，如果apply binlog不及时，会导致应用变更日志的速度无法跟上copy table，在高并发场景下不适用。

虽然gh-ost设置了优先级apply binlog高于copy row，**但是其apply binlog这个阶段是单线程的，不是MTS**，因此如果原表一直压力很大，那么gh-ost DDL将无法完成

**和pt-online-schema-change对比**

1. 表没有写入并且参数为默认的情况下，二者DDL操作时间差不多，毕竟都是copy row操作。

2. 表有大量写入的情况下，因为pt-osc是多线程处理的，很快就能执行完成，而gh-ost是模拟“从”单线程应用的，极端的情况下，DDL操作非常困难的执行完毕。

可以看出，虽然gh-ost不需要触发器，对于主库的压力和性能影响也小很多，但是针对高并发的场景进行DDL效率还是比pt-osc低，所以还是**需要在业务低峰的时候处理**。

gh-ost和pt-osc性能对比测试
https://blog.csdn.net/poxiaonie/article/details/75331916

另外，gh-ost的社区活跃度一般，更新较慢：

![26](https://i.postimg.cc/g2m60CML/26.png)

![27](https://i.postimg.cc/SKK26Wby/27.png)

## 8. 参考文档

https://github.com/github/gh-ost
https://www.cnblogs.com/zhoujinyi/p/9187421.html
https://opensource.actionsky.com/20190918-mysql/

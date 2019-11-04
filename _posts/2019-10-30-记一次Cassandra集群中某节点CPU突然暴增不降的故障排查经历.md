---
layout:     post
title:      记一次Cassandra集群中某节点CPU突然暴增不降的故障排查经历
subtitle:  	
date:       2019-10-30
author:     RC
header-img: 
catalog: true
tags:
    - Cassandra
    - Java Thread
    - Trouble Shooting
---

### 正文
#### 事情经过
10月29号下午值中班到公司不久，收到一封NOC同事的报警邮件，上面提到一台数据库的EC2的机器一直处于非常高（90%-99%）的CPU load状态，他简单看了一下，
这台机器上除了Cassandra的java进程吃掉了所有的CPU以外，没有别的不正常进程，所以求助于DBA。

从Kibana的监控来看，这台机器处于高负载的情况已经持续了很久，从中午1点半左右开始，这个时候已经是下午五点多。

公司的产品Cassandra集群是由3个数据中心，3，3，1个节点来组成的，出问题的节点是DC-US-EAST数据中心的，初步诊断下来，

**该node上的Cassandra日志没有明显的错误，节点状态正常（UN）,Heap Size正常（3267.49 / 7987.25）**。

虽然Cassandra作为分布式的数据库，能够满足BASE的基本可用，但是长期的CPU高负载还是让人心急。

进一步对消耗的CPU资源的线程进行诊断：
```
首先找出Cassandra进程内最耗费CPU的线程(当前Cassandra的进程PID=14291):
[tnuser@ec1-usercassandra-01 bin]$ top -Hp 14291
top - 03:05:54 up 34 days, 17:16,  1 user,  load average: 16.17, 16.79, 15.39
Threads: 245 total,  21 running, 224 sleeping,   0 stopped,   0 zombie
%Cpu(s): 97.0 us,  0.0 sy,  3.0 ni,  0.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
KiB Mem : 31962008 total,   373056 free, 17172420 used, 14416532 buff/cache
KiB Swap: 10484732 total, 10484728 free,        4 used. 14088248 avail Mem 

  PID USER      PR  NI    VIRT    RES    SHR S %CPU %MEM     TIME+ COMMAND                                                                                                                                                           
14688 tnuser    20   0   53.7g  18.0g   2.4g R 99.9 59.2  69:03.28 java                                                                                                                                                              
14746 tnuser    20   0   53.7g  18.0g   2.4g R 68.8 59.2 252:59.71 java                                                                                                                                                              
14687 tnuser    20   0   53.7g  18.0g   2.4g R 56.2 59.2 168:30.45 java                                                                                                                                                              
14663 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2  96:18.21 java                                                                                                                                                              
14674 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2 146:03.38 java                                                                                                                                                              
14676 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2 199:47.53 java                                                                                                                                                              
14677 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2  18:07.87 java                                                                                                                                                              
14680 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2  17:07.13 java                                                                                                                                                              
14682 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2  59:32.14 java                                                                                                                                                              
14685 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2 238:52.59 java                                                                                                                                                              
14690 tnuser    20   0   53.7g  18.0g   2.4g R 50.0 59.2 236:24.36 java                                                                                                                                                              
14686 tnuser    20   0   53.7g  18.0g   2.4g R 43.8 59.2  14:01.77 java                                                                                                                                                              
14664 tnuser    20   0   53.7g  18.0g   2.4g R 31.2 59.2 106:14.20 java                                                                                                                                                              
14667 tnuser    20   0   53.7g  18.0g   2.4g R 31.2 59.2  28:48.98 java                                                                                                                                                              
14678 tnuser    20   0   53.7g  18.0g   2.4g R 31.2 59.2  16:59.07 java                                                                                                                                                              
 8072 tnuser    24   4   53.7g  18.0g   2.4g R 25.0 59.2 213:03.65                                                                                              
```
```
将其中消耗CPU时间较多的java线程的PID转换为16进制:
[tnuser@ec1-usercassandra-01 bin]$ printf "%x\n" 8072 14690 14685 14676 14674 14687 14746 14664
1f88
3962
395d
3954
3952
395f
399a
3948
```
```
用jstack命令输出Cassandra进程的堆栈信息，然后根据线程ID的十六进制值grep,看看是什么类型的线程吃掉了CPU
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 1f88
"CompactionExecutor:15195" #4235509 daemon prio=1 os_prio=4 tid=0x00007f0d1eaa6800 nid=0x1f88 runnable [0x00007f10f1616000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 3962
"ReadStage:28" #386 daemon prio=5 os_prio=0 tid=0x00007f0a0ab90000 nid=0x3962 runnable [0x00007f07f87ec000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 395d
"ReadStage:23" #381 daemon prio=5 os_prio=0 tid=0x00007f0a0ab86000 nid=0x395d runnable [0x00007f07f8930000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 3954
"ReadStage:14" #372 daemon prio=5 os_prio=0 tid=0x00007f0a0ab73000 nid=0x3954 runnable [0x00007f0954082000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 3952
"ReadStage:12" #370 daemon prio=5 os_prio=0 tid=0x00007f0a0ab6f000 nid=0x3952 runnable [0x00007f0954105000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 395f
"ReadStage:25" #383 daemon prio=5 os_prio=0 tid=0x00007f0a0ab8a000 nid=0x395f runnable [0x00007f07f88af000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 399a
"MiscStage:1" #442 daemon prio=5 os_prio=0 tid=0x00007f0a0ac04000 nid=0x399a runnable [0x00007f07f79b4000]
[tnuser@ec1-usercassandra-01 bin]$ ./jstack 14291 | grep 3948
"ReadStage:2" #360 daemon prio=5 os_prio=0 tid=0x00007f0a0ab5a000 nid=0x3948 runnable [0x00007f095438f000]
```
可以看到Cassandra的ReadStage线程是消耗时间较高的，并且有很多个，**这意味着该节点在集群中将越来越落后**
```
用nodetool tpstats验证：
[tnuser@ec1-usercassandra-01 bin]$ /usr/local/cassandra/bin/nodetool tpstats
Pool Name                    Active   Pending      Completed   Blocked  All time blocked
MutationStage                     0         0       39351959         0                 0
ReadStage                        15        15      127331539         0                 0
RequestResponseStage              0         0      119939106         0                 0
ReadRepairStage                   0         0         335170         0                 0
ReplicateOnWriteStage             0         0              0         0                 0
MiscStage                         1         8          15042         0                 0
AntiEntropySessions               0         0           1792         0                 0
HintedHandoff                     0         0             22         0                 0
FlushWriter                       0         0          48039         0              1856
MemoryMeter                       0         0           6798         0                 0
GossipStage                       0         0       11333432         0                 0
CacheCleanupExecutor              0         0              0         0                 0
InternalResponseStage             0         0          12544         0                 0
CompactionExecutor                1         1         651145         0                 0
ValidationExecutor                0         0          15041         0                 0
MigrationStage                    0         0              0         0                 0
commitlog_archiver                0         0              0         0                 0
AntiEntropyStage                  0         0         106319         0                 0
PendingRangeCalculator            0         0             11         0                 0
MemtablePostFlusher               0         0         139417         0                 0
```
15个pending状态，表示其他节点一直尝试和该节点交流，但是该节点已经无法读到本地的信息。

这种情况一般是呈spike状出现的，意味着集群的node数量不够或者系统参数没有调好，现在是美国凌晨的低峰期，而且这个情况之前几乎没有遇到过，显然不是这两者的问题。

到下午6点多钟，当集群的daily备份在DC-US-SJC中心的ec3-usercassandra-01上完成之后，此时Pending状态的ReadStage线程已经到了3W6+:
![1](https://i.postimg.cc/q7L5RwRJ/block-Read-thread.jpg)
这时已经是美国时间凌晨3点多，美国那边的Cassandra owner的On call虽然是可用的，但是我还是**执行了问题节点的重启**。

重启之后节点一切恢复正常，应该是虚惊一场了。

从第二天美国同事的分析来看，中国时间29号下午1点半左右，问题节点的Streaming线程就死掉了：
```
ERROR [STREAM-IN-/10.186.100.179] 2019-10-28 22:25:20,986 StreamSession.java (line 467) [Stream #7fa879d0-fa0c-11e9-9aff-c3df58afc24e] Streaming error occurred
java.lang.RuntimeException: Outgoing stream handler has been closed
                at org.apache.cassandra.streaming.ConnectionHandler.sendMessage(ConnectionHandler.java:126)
                at org.apache.cassandra.streaming.StreamSession.maybeCompleted(StreamSession.java:667)
                at org.apache.cassandra.streaming.StreamSession.taskCompleted(StreamSession.java:619)
                at org.apache.cassandra.streaming.StreamTransferTask.complete(StreamTransferTask.java:71)
                at org.apache.cassandra.streaming.StreamSession.received(StreamSession.java:542)
                at org.apache.cassandra.streaming.StreamSession.messageReceived(StreamSession.java:424)
                at org.apache.cassandra.streaming.ConnectionHandler$IncomingMessageHandler.run(ConnectionHandler.java:245)
                at java.lang.Thread.run(Thread.java:748)
```
这个故障很可能是当天美国时间晚上9点，也就是中国29号中午12点的在DC-US-SJC中心的ec3-usercassandra-01上执行的每月node repair任务引起的。

我们来看看sreaming线程的官方解释：
```
“Streaming” is a component which handles data (part of SSTable file) exchange among nodes in the cluster.
When xxx.. When you run nodetool repair, nodes exchange out-of-sync data using streaming.
```

这也解释了为什么当时阻塞了那么多读线程了。

整个Kibana的CPU load监控曲线：
![1](https://i.postimg.cc/mbLPkF60/QQ-20191030205842.jpg)

#### 总结
1.追溯故障发生原因时，不要从log的末尾找起，应该锁定开始出现异常（征兆）的时间点（这个case而言就是中国时间13:30，CPU load开始升高的起点），在这个点附近搜索蛛丝马迹

2.不是owner的part也要勤于学习，不然根本帮不上忙！





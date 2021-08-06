---
layout:     post
title:      MySQL与NUMA小结
subtitle:  	
date:       2021-06-06
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - Linux
    - NUMA
---


### NUMA是什么

NUMA（Non-Uniform Memory Access，非一致性内存访问） NUMA 服务器的基本特征是 Linux 将系统的硬件资源划分为多个软件抽象，称为节点（Node），每个节点上有单独的 CPU、内存和 I/O 槽口等。CPU 访问自身 Node 内存的速度将远远高于访问远地内存（系统内其它节点的内存）的速度(**约为2-3倍**)。

其出现的背景在于随着摩尔定律的持续发挥作用，服务器 CPU 主频越来越高，并且开始往多核架构的方向狂奔。而之前的SMP架构不能很好地发挥硬件的性能提升，NUMA应运而生，它融合了 SMP 和 MPP 架构的特点，能够让服务器提供更加出色的 CPU 计算能力。

上述的描述比较抽象，简单来说，在物理分布上，**NUMA node的处理器和内存块的物理距离更小，因此访问也更快**。

我们可以看下具体的CPU物理设计(图片源于网络)：

![1](https://i.postimg.cc/T1yhg7dC/1.jpg)

上图是一个Intel Xeon E5 CPU的架构信息，左右两边的大红框分别是两个NUMA，每个NUMA的core访问直接插在自己红环上的内存必然很快，如果访问插在其它NUMA上的内存还要走两个红环之间上下的黑色箭头线路，所以要慢很多。

### 老生常谈之swap insanity

我们知道，相对于物理内存，在linux下还有一个虚拟内存的概念，虚拟内存就是为了满足物理内存的不足而提出的策略，它是利用磁盘空间虚拟出的一块逻辑内存，**用作虚拟内存的磁盘空间被称为交换空间（Swap Space）**。

通过设置swappiness参数，可以控制系统在物理内存不足时，使用SWAP的概率：

```html
$ cat /proc/sys/vm/swappiness
60
# 默认为60，该值越小，使用SWAP的概率越低，建议设置为1
$ vim /etc/sysctl.conf
vm.swappiness = 1
# sysctl -p
cat /proc/sys/vm/swappiness
```

在某些情况下，即使物理内存看上去还很充裕，如buff/cache+free还有大量剩余，系统本来可以删除cache中的page来回收内存，但swap已经开始大量使用，这种现象被称为SWAP Insanity。

而NUMA之所以和MySQL的swap insanity有关系，是因为MySQL作为一个单进程多线程的程序，在开启的 NUMA 服务器中，内存被分配到各 NUMA Node 上，请求进程会从当前所处的 CPU 的 Node 请求分配内存，MySQL 进程只能消耗所在节点的内存，当某个需要消耗大量内存的进程耗尽了所处的 Node 的内存时，其默认的**远古策略**会优先淘汰 Local 内存中无用的 Page，导致产生 swap，不会从远程 Node 分配内存，进而引起数据库内存访问的命中率下降，系统响应速度降低等现象。

### 到底该不该使用NUMA

在2010年的一篇名叫 [The MySQL “swap insanity” problem and the effects of the NUMA architecture](https://blog.jcole.us/2010/09/28/mysql-swap-insanity-and-the-numa-architecture/) 的文章中，指出

![2](https://i.postimg.cc/ZKVLNyCW/2.png)

在开启NUMA的Linux系统中，对于MySQL等占用整个物理内存的进程，当其中一个node的内存不足时，会倾向于在local节点上刷掉page来释放内存而不是去remote node上使用空闲的内存，因此造成了swap insanity的情况，导致数据库性能抖动和下降。

随后，文章给出了当时的3种方法来规避这个问题：

- 使用 numactl --interleave=all CMD 启动数据库服务，以实现数据库进程无视 NUMA 关于 CPU 内存分配的策略，可以使得各个 CPU 区域的内存均匀分配

```html
$ numactl --interleave=all ./bin/mysqld_safe --defaults-file=/etc/my.cnf &
```

- 在启动数据库进程前，采用清空操作系统的环境方式，以释放更多的内存资源

```html
$ sysctl vm.drop_caches=1
# 该操作可能会引起系统负载的震荡
```

- 彻底关掉NUMA

```html
1.硬件层，在 BIOS 中设置关闭；
2. OS 内核层，在 Linux Kernel 启动参数中加上 numa=off 后重启服务器；
For RHEL 7：
编辑 /etc/default/grub 文件的 kernel 行, 在末尾加上numa=off
$ vi /etc/default/grub
GRUB_CMDLINE_LINUX="rd.lvm.lv=rhel_vm-210/root rd.lvm.lv=rhel_vm-210/swap vconsole.font=latarcyrheb-sun16 crashkernel=auto  vconsole.keymap=us rhgb quiet numa=off
RHEL7/CentOS7 必须要重建 GRUB 配置文件才能生效：
$ grub2-mkconfig -o /etc/grub2.cfg
```

我们使用NUMA的时候期望是：优先使用本NUMA上的内存，如果本NUMA不够了不要优先回收PageCache而是优先使用其它NUMA上的内存，而在古老的2010年，Linux看上去在识别到NUMA架构后，默认的内存分配方案就是：优先尝试在请求线程当前所处的CPU的Local内存上分配空间。如果local内存不足，优先淘汰local内存中无用的Page（Inactive，Unmapped）。然后才到其它NUMA上分配内存。

这里有一个比较重要的参数**zone_reclaim_mode**：

- 用来管理当一个内存区域(zone)内部的内存耗尽时，是从其内部进行内存回收还是可以从其他zone进行回收的选项

- 默认为0：Allocate from all nodes before reclaiming memory， 在回收内存之前从其他node使用内存

- 为1时：Reclaim memory from local node vs allocating from next node， 回收本地node的内存rather than 从其他节点使用剩余内存

而实际上，在2014年前的kernel代码中，当开启了NUMA时(node distance比较大），内存不足时将强制把 zone_reclaim_mode设为1(图片源于网络)：

![3](https://i.postimg.cc/j5DjMmXV/3.png)

此时就算设置了zone_reclaim_mode设为0也没有任何作用，因此有了2010年的著名文章。

此bug随后在2014年及之后的kernel版本中修复(图中已经注释掉)。

### MySQL与NUMA

MySQL除了在启动时指定NUMA的策略以外，在5.7.9版本以后，新增了参数innodb_numa_interleave。

根据官方文档的描述：当设置innodb_numa_interleave=1的时候，对于mysqld进程的numa内存分配策略设置为MPOL_INTERLEAVE，而一旦Innodb buffer pool分配完毕，则策略重新设置回MPOL_DEFAULT。当然这个参数是否生效，必须建立在mysql是在支持numa特性的linux系统上编译的基础上。

关于NUMA的内存分配策略：

![4](https://i.postimg.cc/VLCCfrXy/4.png)

其中，MySQL 5.7.19 版本以后的免编译的二进制包开始支持 innodb_numa_interleave 参数。

我们来看一下实际运行的MySQL服务器上的内存，NUMA， SWAP等相关情况：

![5](https://i.postimg.cc/FRw0pj0Z/5.png)

图中可以看出：

- 系统的SWAP空间已经到达了63G，而空余的物理内存还剩余45G

- 系统开启了NUMA， 节点数为2， CPU的核数为40

- 系统的NUMA内存分配策略为默认的MPOL_DEFAULT，导致Node1和Node2的内存分配不均

看上去问题**似乎**很严重了？

我们先看下SWAP是否真的在频繁使用：

```html
1.top命令查看
$ top
按f进入控制面板，控制键盘上下移动到SWAP    = Swapped Size (KiB)，按d
随后键盘控制向右选中改行，拖动到command之前，esc退出面板
2.vmstat命令查看
$ vmstat 2
观察si和so是否为0
3.一个简单脚本
#!/bin/bash

cd /proc

for pid in [0-9]*; do
    command=$(cat /proc/$pid/cmdline)

    swap=$(
        awk '
            BEGIN  { total = 0 }
            /Swap/ { total += $2 }
            END    { print total }
        ' /proc/$pid/smaps
    )

    if (( $swap > 0 )); then
        if [[ "${head}" != "yes" ]]; then
            echo -e "PID\tSWAP\tCOMMAND"
            head="yes"
        fi

        echo -e "${pid}\t${swap}\t${command}"
    fi
done

```

![6](https://i.postimg.cc/j2Xd2Tq7/6.png)

由此可以判断SWAP空间几乎没有被使用，系统的内存是足够的

再看下MySQL进程在哪一个node：

```html
查看MySQL进程中的线程使用的cpu编号
同上，使用top -Hp命令，选中P       = Last Used Cpu (SMP)
$ top -Hp 2556
将得到的P值写入文本文件，uniq sort一下就得到了目前进程使用的CPU编号
或者
pidstat -p pid -t 1
```

![7](https://i.postimg.cc/y8RtyP9f/7.png)

通过对比，明显为Node1中绑定的0 1 2 3 4 5 6 7 8 9 20 21 22 23 24 25 26 27 28 29号CPU

因此MySQL进程所在的Node为Node1

而服务器的默认的/proc/sys/vm/zone_reclaim_mode为0，可以看出当Node1内存不足时，确实是从Node2上分配了内存到Node1，而不是直接刷新FS的page cache，符合预期

这里之所以查看了MySQL所在Node绑定的CPU，是因为目前数据库服务器(特别是云上的RDS等)倾向于**按NUMA绑定core**，号称性能可以大幅提升

另外，测试者还声称如果BIOS层面关闭NUMA，则关闭后OS无法感知CPU的物理架构，也就是没有办法就近分配内存，带来的问题就是没法让性能最优，或者用户能感知到RT上的抖动（如果是2个NUMA节点的话，平均会有50%的RT偏高）

> 当下很多云计算系统的任务管理器会倾向于使用CPU绑定（CPU affinity）技术为不同的任务分配CPU，这样的又是是可以减少由于CPU频繁切换导致的性能损失。出于减少碎片化的目的，这样的系统往往习惯于连续分配CPU core。但一旦NUMA策略于CPU分配策略出现冲突，往往就会出现某些应用必须跨socket访问远端内存的错误设置。

### 结论

- 在新版本内核的Linux服务器上开启NUMA特性，并设置zone_reclaim_mode为0是**没有任何坏处**的

- 如果将MySQL按NUMA绑定CPU core，**性能将得到较大提升**

- 如果关闭NUMA特性，并不会比第一点的配置快，并且**可能会有性能抖动**

### 参考

[十年后数据库还是不敢拥抱NUMA?](https://zhuanlan.zhihu.com/p/387117470)

[浅谈 NUMA 与 MySQL](https://zhuanlan.zhihu.com/p/366997634)

[NUMA架构与数据库的一些思考](https://www.modb.pro/db/28677)

[SWAP的罪与罚](https://blog.huoding.com/2012/11/08/198)

[NUMA的优势和陷阱](https://zhuanlan.zhihu.com/p/71067706)
---
layout:     post
title:      Redis Learning Note 1
subtitle:  	Redis install and configure, analysis data types of Redis, backup and restore, master-slave relationship, Redis Sentinel failover 
date:       2018-09-25
author:     RC
header-img: img/post-bg-redis-web-1.jpg
catalog: true
tags:
    - DBA
    - Redis 
    - NoSQL
---

# 1.Introduction
## 1.1 What is Redis
Redis(**Remote Dictionary Sever**) is an open-source, key-value store, memory cache, NoSQL database which is compiled by Standard C and is often ranked the most popular key-value database.
## 1.2 Advantages
a. **High performance**, Redis can read 110000 times per second and can write 81000 times per second at most. 

b. **Supported for abundant of datatypes**, including Strings, Lists, Hashes, Sets and Sorted Sets.

c. **Data persistence**, Redis can sync data in memory to datafiles on disk after some particular-time, have done how many times of changes.

d. **Atomicity**, every single operation in the transaction is atomic, that means all operations are either not done at all in failure or complete by all in success.

e. **High Availability**, Redis is supported for Master-Slave mode data backup and Sentinel Cluster for auto failover.

f. **Other features**, Redis contains functions of publish/subscribe, informer, key expired time and so on. 
## 1.3 What is the content
In the following parts, this document will show how to install and configure Redis, analysis data types of Redis, do the backup and restore, build a master-slave relationship between servers, a Redis Sentinel failover practice and so on.

# 2.Redis installation and configure
## 2.1 Installation
```
$ wget http://download.redis.io/releases/redis-2.8.24.tar.gz
$ tar -xvzf redis-2.8.24.tar.gz
$ mv redis-2.8.24 /usr/local/redis/
$ cd redis
$ make
```
## 2.2 Configuration
```
$ pwd
/usr/local/redis
$ vim redis.conf
logfile "redis-test.log"
dbfilename dump_test.rdb
$ echo never > /sys/kernel/mm/transparent_hugepage/enabled
$ vim /etc/sysctl.conf
vm.overcommit_memory = 1
net.core.somaxconn= 1024
$ sysctl -p
$ vim /etc/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled
$ ulimit -n 65535
```
## 2.3 Start service
```
$ cd src/
$ ./redis-server ../redis.conf &
[1] 1950
$ cat redis-test.log
[31553] 12 Jun 16:10:14.250 # Server started, Redis version 2.8.24
[31553] 12 Jun 16:10:14.250 * DB loaded from disk: 0.000 seconds
[31553] 12 Jun 16:10:14.250 * The server is now ready to accept connections on port 6379
```

# 3.Brief analysis of Redis data types
## 3.1 Hash
### 3.1.1 What is Hash
 Hash is a data structure. The general translation is **"hash"(散列)**, and there is a direct transliteration of "hash". Due to the features of Anti-collision ability and Anti tampering ability, hash is considering as **irreversible** and in fact we can regard it as a method of information Lossy compression.
### 3.1.2 What is hash function 
A hash function is any function that can be used to map data of arbitrary size to data of fixed size. The values returned by a hash function are called hash values, hash codes, digests, or simply hashes. One use is a data structure called a hash table, widely used in computer software for **rapid data lookup**.
### 3.1.3 What is hash table
 A hash table (hash map) is a data structure which implements an associative array abstract data type, a structure that can **map keys to values**. A hash table uses a hash function to compute an index into an array of buckets or slots, from which the desired value can be found.
### 3.1.4 What is Redis hash
Redis hash is a string type field and value table. It is especially suitable for the storage object. With each field of the object into a single string type, hash type storage will occupy **less memory**, and convenient access to the entire object.
### 3.1.5 Example
```
127.0.0.1:6379> hmset product name 'computer' price '3200' size '14inch'  
OK
127.0.0.1:6379> hgetall product
1) "name" //field1
2) "computer" //value1
3) "price" //field2
4) "3200" //value2
5) "size" //field3
6) "14inch" //value3
```

## 3.2 List
### 3.2.1 What is Singly linked list
![1](https://s1.ax1x.com/2018/09/25/iK6PR1.png)
*A linked list whose nodes contain two fields: an integer value and a link to the next node. The last node is linked to a terminator used to signify the end of the list.*
### 3.2.2 What is Redis List
In my opinion, the Redis list as a data type **is very similar to the definition of singly linked list**, but please be aware of that the L/RPUSH command with multi values should be considered as L/RPUSH a single value for repeat times, also, when we first put values in a null list, there is no difference between LPUSH and RPUSH.
### 3.2.3 Example
```
127.0.0.1:6379> llen list2
(integer) 0
127.0.0.1:6379> lpush list2 a b c 
(integer) 3
127.0.0.1:6379> lrange list2 0 -1
1) "c"
2) "b"
3) "a"
(lpush list2 a b c == lpush a + lpush b + lpush c)
127.0.0.1:6379> rpush list2 d
(integer) 4
127.0.0.1:6379> lpush list2 e
(integer) 5
127.0.0.1:6379> lrange list2 0 -1
1) "e"
2) "c"
3) "b"
4) "a"
5) "d"
```


## 3.3 Sorted Set
### 3.3.1 What is Redis sorted set
Sorted Set is an important data structure of Redis, which is used to **store data that needs sorting**. For example, the rankings, the scores of a class, the wages of a company, the posts of a forum, etc. In an ordered set, each element has score (weight) to sort the elements. It has three elements: key, member, and score. Taking language achievement as an example, key is the name of the examination (mid-term exam, final examination, etc.), member is the student's name, and score is the result. The sorted set is often designed for sorting and convergence.
### 3.3.2 Example of sorting
```
127.0.0.1:6379> zadd mid_test 70 "Tom"
(integer) 1
127.0.0.1:6379> zadd mid_test 80 "Jerry"
(integer) 1
127.0.0.1:6379> zadd mid_test 90 "Jack"
(integer) 1
127.0.0.1:6379> zrange mid_test 0 -1 withscores //ranking list by positive sequence
1) "Tom"
2) "70"
3) "Jerry"
4) "80"
5) "Jack"
6) "90"
127.0.0.1:6379> zrangebyscore mid_test 90 100 withscores // piecewise statistics
1) "Jack"
2) "90"
```
### 3.3.3 Example of convergence(ZINTERSTORE)
```
127.0.0.1:6379> zadd final_test 65 "Tom" //final test of the 3 old classmates and the new comer 
(integer) 1 
127.0.0.1:6379> zadd final_test 75 "Jerry"
(integer) 1
127.0.0.1:6379> zadd final_test 85 "Jack"
(integer) 1
127.0.0.1:6379> zadd final_test 100 "Jill"
(integer) 1
127.0.0.1:6379> zinterstore sum_point 2 mid_test final_test
(integer) 3
127.0.0.1:6379> zrange sum_point 0 -1 withscores //ranking list of the sum scores of 2 exams
1) "Tom"
2) "135"
3) "Jerry"
4) "155"
5) "Jack"
6) "175"
```
(Note that although Jill has 100 score in the final test, the ZINTERSTORE means A and B's member will be added to C, and its score is equal to the sum of score in A and B.
**Not at the same time in the member of A and B, not in C**)
### 3.3.4 Example of convergence(ZUNIONSTORE)
```
127.0.0.1:6379> zadd programmer 2000 Jack
(integer) 1
127.0.0.1:6379> zadd programmer 3000 Jill
(integer) 1
127.0.0.1:6379> zadd programmer 4000 Tom //programmers’ salary
(integer) 1
127.0.0.1:6379> zadd manager 5000 Tom
(integer) 1
127.0.0.1:6379> zadd manager 6000 Henry
(integer) 1
127.0.0.1:6379> zadd manager 7000 Mary //managers’ salary
(integer) 1
127.0.0.1:6379> zunionstore salary 2 programmer manager
(integer) 5
127.0.0.1:6379> zrange salary 0 -1 withscores
 1) "Jack"
 2) "2000"
 3) "Jill"
 4) "3000"
 5) "Henry"
 6) "6000"
 7) "Mary"
 8) "7000"
 9) "Tom"
10) "9000" //The salary of the two men of the same name has been calculated in sum of one person named “Tom”
```
(The zunionstore means All member of A will be added to C, and its score is equal to A.
All member of B will be added to C, and its score is equal to B.
If A and B have member in common, **their score is equal to the sum of score in A and B**.)
### 3.3.5 Parameter AGGREGATE of ZINTERSTORE/ZUNIONSTORE
ZINTERSTORE and ZUNIONSTORE have a parameter of AGGREGATE, which represents the way of aggregation of result sets, and one of them is SUM, MIN and MAX. The default value is SUM. Without specifying the aggregation mode, the **default value is SUM**, that is, summation.

# 4. Redis backup and restore 
## 4.1 Data backup
```
127.0.0.1:6379> save //create dump file directly
OK
127.0.0.1:6379> bgsave //create dump file in background
Background saving started
```
*Please note that the backup file name should also be the same on the restore server, it is configured in redis.conf as 

#The filename where to dump the DB

**dbfilename dump_test.rdb**

## 4.2 Data restore 
a. Copy the dump file on source server to target server:
```
$ pwd
/usr/local/redis/src
$ scp dump_test.rdb xxx@xx.xx.xx.xx:/tmp/
```
b. Shutdown Redis DB on target server:
```
127.0.0.1:6379> shutdown
not connected>
```
c. Remove the origin dump file on target server, change the owner of the new target file and move it to the Redis **running directory**:
```
$ pwd 
/usr/local/redis/src
$ rm -rf dump_test.rdb
$ chown root:root dump_test.rdb
$ mv dump_test.rdb /usr/local/redis/src/
```
d. Start Redis DB and check result
```
$ ./redis-server ../redis.conf &
[1] 2990
$ ./redis-cli
127.0.0.1:6379> dbsize
(integer) 16 
127.0.0.1:6379> keys *
 1) "hashtable1"
 2) "foo"
 3) "mid_test"
 4) "programmer"
 5) "book-name"
 6) "final_test"
 7) "tag"
 8) "echo1"
 9) "set1"
10) "list2"
11) "zset1"
12) "salary"
13) "manager"
14) "product"
15) "list1"
16) "sum_point"
$ ./redis-cli 
127.0.0.1:6379> auth redis
OK
127.0.0.1:6379> dbsize
(integer) 16
$ cat redis-test.log
[2990] 20 Jun 19:41:05.652 # Server started, Redis version 2.8.24
[2990] 20 Jun 19:41:05.653 * DB loaded from disk: 0.000 seconds
[2990] 20 Jun 19:41:05.653 * The server is now ready to accept connections on port 6379
// No error in DB log
```

# 5. Redis Master-Slave replication
## 5.1 Introduction of Redis replication
In order to obtain **greater storage capacity and higher concurrent access traffic**, the distributed database will disperse the data to multiple storage nodes through a network connection instead of the original centralized database data storage. In order to solve the problem of single point database, Redis will generate multiple data copies and deploy them to other nodes to achieve **high availability**, realize the redundancy of the data, and ensure the high reliability of data and services.
## 5.2 How to set up Replication 
a. Configure in redis.conf file and start Redis DB with the configure file:
```
slaveof <masterip> <masterport>
```
b. Start Redis with option:
```
redis-server redis.conf --slaveof <masterip> <masterport> &
```
c. Directly point to master in a running node:
```
slaveof <masterip> <masterport>
```
## 5.3 Replication info
### 5.3.1 Replication info in log file
```
$ ./redis-cli 
127.0.0.1:6379> dbsize
(integer) 2
127.0.0.1:6379> slaveof xx.xx.xx.56 6379
OK
127.0.0.1:6379> dbsize
(integer) 16
```
* Please note that if the master server has set the authentication to login, you must **configure the master password in the redis.conf file before you set the replication**:
```
masterauth redis
```
or you will get the error below:
```
[3041] 20 Jun 20:34:59.504 * Connecting to MASTER xx.xx.xx.xx:6379
[3041] 20 Jun 20:34:59.504 * MASTER <-> SLAVE sync started
[3041] 20 Jun 20:34:59.505 * Non blocking connect for SYNC fired the event.
[3041] 20 Jun 20:34:59.505 * Master replied to PING, replication can continue...
[3041] 20 Jun 20:34:59.505 # Unable to AUTH to MASTER: -ERR invalid password
```
* Normal replication info in Redis DB log:
```
[21482] 15 Jun 17:34:19.407 * Connecting to MASTER xx.xx.xx.xx:6379
[21482] 15 Jun 17:34:19.408 * MASTER <-> SLAVE sync started
[21482] 15 Jun 17:34:19.408 * Non blocking connect for SYNC fired the event.
[21482] 15 Jun 17:34:19.409 * Master replied to PING, replication can continue...
[21482] 15 Jun 17:34:19.409 * Partial resynchronization not possible (no cached master)
[21482] 15 Jun 17:34:19.410 * Full resync from master: 983d258e10f8c5831f47e501d45c2ab36bca88a6:1
[21482] 15 Jun 17:34:19.478 * MASTER <-> SLAVE sync: receiving 287 bytes from master
[21482] 15 Jun 17:34:19.478 * MASTER <-> SLAVE sync: Flushing old data
[21482] 15 Jun 17:34:19.478 * MASTER <-> SLAVE sync: Loading DB in memory
[21482] 15 Jun 17:34:19.479 * MASTER <-> SLAVE sync: Finished with success
```
### 5.3.2 Replication info in DB
On master server:
```
127.0.0.1:6379> info replication 
```
```
# Replication
role:master //role of this node in replication
connected_slaves:2 //connected number of slaves
slave0:ip=xx.xx.xx.55,port=6379,state=online,offset=630503,lag=0 //info of slave1
slave1:ip=xx.xx.xx.66,port=6379,state=online,offset=630503,lag=0 //info of slave2
master_repl_offset:630503 // offset of the master node	
//the following info is for common configuration
repl_backlog_active:1 //state of the replicating buffer
repl_backlog_size:1048576 //size of the replicating buffer
repl_backlog_first_byte_offset:2 //offset of the replicating buffer
repl_backlog_histlen:630502 //effective data length of the existed replicating buffer
```
On slave server:
```
127.0.0.1:6379> info replication 
```
```
# Replication
role:slave //role of the node
master_host:xx.xx.xx.56 //master’s IP
master_port:6379 //master’s port
master_link_status:up //connection state with master
master_last_io_seconds_ago:4 //last time interval between master and this slave by second
master_sync_in_progress:0 // whether the node is synchronizing the RDB file of the master node in full volume
slave_repl_offset:632771 //offset of the replication
slave_priority:100 //priority of the slave
slave_read_only:1 //read-only option of the slave
connected_slaves:0 //number of slaves of this current slave node
master_repl_offset:0 //replication offset of the current slave as master
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0
```
## 5.4 Read-only option of slave DB
```
127.0.0.1:6379> config get slave-read-only
1) "slave-read-only"
2) "yes"
```
```
127.0.0.1:6379> set fff ggg
(error) READONLY You can't write against a read only slave.
```
We can configure this option in redis.conf file:
```
slave-read-only yes
```
(You can configure a slave instance to accept writes or not. Writing against
a slave instance may be useful to store some **ephemeral** data (because data
written on a slave will be easily **deleted** after **resync** with the master) but
may also cause problems if clients are writing to it because of a
**misconfiguration**.)Or:
```
127.0.0.1:6379> config set slave-read-only no
OK
```
## 5.5 Cut-off of the replication
```
127.0.0.1:6379> slaveof no one
OK
```
The log of slave will print:
```
[21482] 20 Jun 23:27:36.338 # Connection with master lost.
[21482] 20 Jun 23:27:36.338 * Caching the disconnected master state.
[21482] 20 Jun 23:27:36.338 * Discarding previously cached master state.
[21482] 20 Jun 23:27:36.339 * MASTER MODE enabled (user request from 'id=22 addr=127.0.0.1:41930 fd=7 name= age=5 idle=0 flags=N db=0 sub=0 psub=0 multi=-1 qbuf=0 qbuf-free=32768 obl=0 oll=0 omem=0 events=r cmd=slaveof')
```
The role of this node will **change to master**:
````
127.0.0.1:6379> info replication 
# Replication
role:master
*The log of the master will print:
[31553] 20 Jun 23:27:36.336 # Connection with slave xx.xx.xx.55:6379 lost.
```
## 5.6 Option of min-slaves
The two configure option min-slaves-to-write and min-slaves-max-lag **can protect master node from executing write command in an unsafety situation**.
```
127.0.0.1:6379> config get min-slaves-to-write
1) "min-slaves-to-write"
2) "3" //master node will refuse all write requests if number of slave node is less than 3
127.0.0.1:6379> config get min-slaves-max-lag
1) "min-slaves-max-lag"
2) "10" //master node will refuse all write request if any of the slave node’s lag is greater than 10
```

# 6. Redis Sentinel
## 6.1 Disadvantages of Redis Replication
a. Once the main node goes down, one of the following nodes need to be promoted to the main node, and the main node address for the application needs to be modified, and all the slave nodes need to be ordered to copy the new main nodes. The whole process needs to be manually intervened.

b. The writing ability of the main node is limited by the single machine.

c. The storage capacity of the main node is limited by the single machine.

Redis has a solution for the first case which is called **Redis Sentinel**	, also has Redis Cluster for the left two ones.

## 	6.2 Introduction of Redis Sentinel
Redis Sentinel is a distributed architecture that contains a set of Sentinel nodes and Redis data nodes. Each Sentinel node monitors the data nodes and the remaining Sentinel nodes. When the nodes are unreachable, the nodes will be marked down.

If the main node is marked as down, the Sentinel node will also choose to "negotiate" with other Sentinel nodes. When most of the Sentinel nodes believe that the main node is unreachable, they will elect a Sentinel node to complete the automatic failover and notify the Redis application side.

The whole process is completely automatic without manual intervention, so it can solve the problem of high availability of Redis.

## 6.3 Redis Sentinel deployment
### 6.3.1 Topology of Redis Sentinel in our case
![2](https://s1.ax1x.com/2018/09/25/iKb70H.png)

Role|IP|Port
:-----:|:-----:|:-----:
Master|xx.xx.xx.56|6379
Slave1|xx.xx.xx.55|6380
Slave2|xx.xx.xx.66|6381
Sentinel1|xx.xx.xx.60|26379
Sentinel2|xx.xx.xx.59|26380

### 6.3.2 Configuration of Sentinel node
```
$ pwd
/usr/local/redis
$ vim sentinel.conf
port 26380 // port of sentinel node
dir "/usr/local/redis/src"
sentinel monitor mymaster xx.xx.xx.56 6379 2 // master’s info as monitor object, mymaster is the nickname, 2 means failover happens if at least two sentinel nodes agree master node is down 
sentinel auth-pass mymaster redis //master authentication 
sentinel down-after-milliseconds mymaster 30000 // master will be considered as down if the time interval is more than 30000ms between 2 ping command
sentinel parallel-syncs mymaster 1 // limit one slave node to sync from new master at one time after failover happens
sentinel failover-timeout mymaster 180000 // time-out of the failover is 180000ms
```
### 6.3.3 Start sentinel node
```
a. $ ./redis-sentinel ../sentinel-26380.conf &
```
```
b. $ ./redis-server ../ sentinel-26380.conf --sentinel &
```
### 6.3.4 Sentinel info
```
./redis-cli -p 26380
127.0.0.1:26380> info sentinel
```
```
# Sentinel
sentinel_masters:1
sentinel_tilt:0
sentinel_running_scripts:0
sentinel_scripts_queue_length:0
master0:name=mymaster,status=ok,address=xx.xx.xx.56:6379,slaves=2,sentinels=2
//sentinels=2 means there are two sentinel nodes started 
```
### 6.3.5 Changes in sentinel config file
The sentinel node will **find slave nodes and other sentinel nodes after start**, it will remove default config in the sentinel.conf file like parallel-syncs, failover-timeout,
And will add a new parameter named epoch:
```
port 26380
dir "/usr/local/redis/src"
sentinel monitor mymaster xx.xx.xx.56 6379 2
sentinel auth-pass mymaster redis
sentinel config-epoch mymaster 0
sentinel leader-epoch mymaster 0
// found 2 slave nodes
sentinel known-slave mymaster xx.xx.xx.55 6380
sentinel known-slave mymaster xx.xx.xx.66 6381
// found 1 sentinel node
sentinel known-sentinel mymaster xx.xx.xx.60 26379 bd43222bc941b21797fa006c84a99c85171850af
sentinel current-epoch 0
```

## 6.4 Redis Sentinel failover simulation
### 6.4.1 Kill master’s Redis process
```
ps aux | grep redis
root       458  0.0  0.0 112664   964 pts/2    S+   20:15   0:00 grep --color=auto redis
root     31553  0.0  0.0 141176  3696 ?        Sl   Jun12   8:31 ./redis-server *:6379
kill -9 31553
ps aux | grep redis
root       460  0.0  0.0 112664   968 pts/2    S+   20:16   0:00 grep --color=auto redis
```

### 6.4.2 Topology of situation now
![3](https://s1.ax1x.com/2018/09/25/iKq89x.png)

### 6.4.3 What happened now
When master’s Redis process is killed, Redis Sentinel determines the **Objectively Down (ODOWN)** of the main node and confirms that the main node is unreachable, then sent the notification to the slave nodes to abort the replication operation of the master node. After the unreachable time of the master node is over 30000ms as configured, **the Redis Sentinel will execute the failover process**. 
### 6.4.4 Sentinel info now
a. About master:
```
127.0.0.1:26379> sentinel masters
1)  1) "name"
    2) "mymaster"
    3) "ip"
    4) "xx.xx.xx.55" 
    5) "port"
    6) "6380"// the master node has changed to node with port 6380
    7) "runid"
    8) "12373cfd2bc6037df8dadb19c9d8f4a311ee981f"
    9) "flags"
   10) "master"
```
b. About slave
```
127.0.0.1:26379> sentinel slaves mymaster
1)  1) "name"
    2) "xx.xx.xx.66:6381"
    3) "ip"
    4) "xx.xx.xx.66" 
    5) "port"
    6) "6381" //the origin slave2 is still salve at now
    7) "runid"
    8) "7ad0a357aaa7a74dcebe05f1a7a32413376afa5d"
    9) "flags"
   10) "slave"
   29) "master-link-status"
   30) "ok"
```
```
2)  1) "name"
    2) "xx.xx.xx.56:6379"
    3) "ip"
    4) "xx.xx.xx.56"
    5) "port"
    6) "6379"
    7) "runid"
    8) ""
    9) "flags"
   10) "s_down,slave,disconnected" // the origin master node has disconnected 
   31) "master-link-status"
   32) "err"
```
We can judge from the above information that after node with port 6379 (old master) is down, **the Sentinels choose the data node with port 6380 to be the new master node**,
the old master disconnected at this moment.

### 6.4.5 Topology of situation after failover
![4](https://s1.ax1x.com/2018/09/25/iKqUDe.png)

### 6.4.6 Start old master’s Redis service again and check result
a. Start Redis service on the node with port 6379
```
./redis-server ../redis.conf &
[1] 513
ps aux | grep redis
root       513  0.1  0.0 140788  2680 pts/2    Sl   21:26   0:00 ./redis-server *:6379
root       531  0.0  0.0 112664   964 pts/2    S+   21:29   0:00 grep --color=auto redis
```
b. Check sentinel info
```
127.0.0.1:26379> sentinel slaves mymaster
1)  1) "name"
    2) "xx.xx.xx.66:6381"
    3) "ip"
    4) "xx.xx.xx.66"
    5) "port"
    6) "6381" // node with port 6381 is still as one of the slaves
    7) "runid"
    8) "7ad0a357aaa7a74dcebe05f1a7a32413376afa5d"
    9) "flags"
   10) "slave"
   29) "master-link-status"
   30) "ok"
```
```
2)  1) "name"
    2) "xx.xx.xx.56:6379"
    3) "ip"
    4) "xx.xx.xx.56"
    5) "port"
    6) "6379" //node with port 6379 is alive after restart, and is degrade to 6380’s slave 
    7) "runid"
    8) "776a565918bbec5101a40891f3c6c1b3659dd9b1"
    9) "flags"
   10) "slave"
   29) "master-link-status"
   30) "ok"
```
### 6.4.7 Final topology
![5](https://s1.ax1x.com/2018/09/25/iKqrCt.png)

## 6.5 Conclusion 
From the simulation of the sentinel failover, we can see that the Redis sentinel can:

a.	**Monitoring**: Sentinel nodes periodically detect whether Redis data nodes and other Sentinel nodes are reachable.

b.	**Notification**: The Sentinel node will notify failover to the application side.

c.	**Failover of the master node**: Can promote the slave node to be new master node after the old master is down and maintain the correct master-slave relationship after that.

d.	**Configuration provider**: In the Redis Sentinel structure, when the client initializes, it connects the Sentinel node set and gets the master node information.

•	 Footnote of the sentinel configuration:
```
sentinel notification-script mymaster /var/redis/notify.sh
// During the failover process, when some warning level Sentinel events occur (means important events, such as subjectively down, objectively down, etc.), the script of the corresponding path will be triggered, and the script will be sent the corresponding event parameters.
```
```
sentinel client-reconfig-script mymaster /var/redis/reconfig.sh
// After the failover ends, the script of the corresponding path will be triggered, and the script will be sent the parameter of the failover result.
```
# 7. Expectation
This document is very rare corner of Redis ice mountain, many contents should be explored in the future like: **Redis Cluster**, Redis heterogeneous cluster migration and so on.






























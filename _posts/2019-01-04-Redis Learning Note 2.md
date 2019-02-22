---
layout:     post
title:      Redis Learning Note Ⅱ
subtitle:  	Redis cluster introduction, deployment and scalability
date:       2019-01-04
author:     RC
header-img: img/post-bg-redis-web-1.jpg
catalog: true
tags:
    - DBA
    - Redis 
    - NoSQL
---

# 7. Redis Cluster
## 7.1 Introduction of Redis Cluster
**Redis Cluster** is a distributed solution for Redis, which is officially launched in **Redis 3.0** and effectively solves the distributed requirements of Redis. 
Cluster architecture can be used to achieve load balancing when single-machine memory, concurrency, traffic and other bottlenecks are encountered.
## 7.2 Data Distribution Theory
Distributed database first solves the problem of mapping the entire data set to multiple nodes according to partitioning rules, that is, dividing the data set into multiple nodes, each node is responsible for a subset of the entire data. 
Common zoning rules include hash partitions and sequential partitions. Redis Cluster uses the virtual slot partitioning in the hash partitioning rule: the virtual slot partitioning ingeniously uses hash space and uses well-dispersed hash functions to map all data into a fixed range of integer sets, defined as slots. 
For example, the range of **Redis Cluster slot is 0~16383**. Slot is the basic unit of data management and migration in cluster. The main purpose of using a large range of slots is to facilitate data splitting and cluster expansion, each node is responsible for a certain number of slots.
## 7.3 Redis Data Distribution Introduction
Redis Cluster uses virtual slot partitioning, and all keys are mapped to **0~16383** according to hash functions, and the formula is calculated by:
```
				  slot=CRC16(key)&16383
```
Each node is responsible for maintaining a portion of the slot and the key value data that the slot maps.
The following chart shows the whole process of mapping the corresponding slot to the corresponding node by calculation formula in a 6 nodes Redis cluster:
![1](https://s2.ax1x.com/2019/02/22/kfVIjP.png)
## 7.4 The Features of Redis Virtual Slot Partition
a. Decoupling the relationship between data and nodes, simplifies the difficulty in expansion and contraction of nodes.

b. The node itself maintains the slot mapping relationship and does not require client or proxy services to maintain the slot partition metadata.

c. Support for mapping queries between nodes, slots and keys for data routing, online scaling and other scenarios.
## 7.5 Redis Cluster Workflow
Redis Cluster is a centerless structure, and each node stores data and the state of the entire cluster. Each node will save information from other nodes and know the slot that other nodes are responsible for. 
It will send **heartbeat** information to other nodes **at regular intervals**, and it can sense the abnormal nodes in the cluster in time.
When the client sends a command related to the database key to any node in the cluster, the node receiving the command calculates which slot the command will process (CRC16 (key) & 16383) and **checks whether the slot is assigned to itself**:

Ⅰ. If the slot in the key is assigned to the current node, then the node executes the command directly.

Ⅱ. If the slot in which the key is located is not assigned to the current node, the node returns a MOVED error to the client, directs the client to redirect to the correct node, and sends again the command you wanted to execute before.
## 7.6 Functional Limitation of Redis Cluster
The Redis cluster is functional limited comparing with stand-alone mode in a way:

a. **Key batch operation support is limited**. For example, MSET/MGET, currently only supports batch operation with key with the same slot value.

b. **Key transaction operations are limited**. It supports multi key transaction operations on the same node and does not support transaction functions distributed over multiple nodes.

c. Key is the minimum granularity of a data partition, so you can't map a large key-valued object to different nodes. Such as: hash, list.

d. **Multi database space is not supported**. Redis supports 16 databases under one machine, and only one database space can be used in cluster mode, that is, DB 0.

e. The replication structure **supports only one layer** and does not support nested tree replication structure.

## 7.7 Build a Redis Cluster
### 7.7.1 Preparing nodes

Node name|Node IP|Port|Role|Slot
:-----:|:-----:|:-----:|:-----:|:-----:
xx-01|xx.xx.xx.58|6379|Master|0-5461
xx-02|xx.xx.xx.59|6380|Master|5462-10922
xx-03|xx.xx.xx.60|6381|Master|10923-16383
xx-04|xx.xx.xx.66|6382|Slave|N/A
xx-01|xx.xx.xx.55|6383|Slave|N/A
xx-02|xx.xx.xx.56|6384|Slave|N/A

```
$ cd /usr/local (as root)
$ wget http://download.redis.io/releases/redis-3.2.11.tar.gz
$ tar -xvzf redis-3.2.11.tar.gz
$ mv redis-3.2.11 /usr/local/redis
$ cd redis
$ make
$ pwd
/usr/local/redis
```
```
$ vim redis.conf
port 6379
pidfile /var/run/redis_6379.pid
logfile "/usr/local/redis/redis-6379.log"
dbfilename dump-6379.rdb
cluster-enabled yes
cluster-config-file nodes-6379.conf
cluster-node-timeout 15000
```
```
$ echo never > /sys/kernel/mm/transparent_hugepage/enabled
$ vim /etc/sysctl.conf
vm.overcommit_memory = 1
net.core.somaxconn= 1024
$ sysctl -p
$ vim /etc/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled
$ ulimit -n 65535
$ pwd
$ /usr/local/redis
mv redis.conf redis-6379.conf
$ cd src/
./redis-server ../redis-6379.conf &
```
```
$ cat redis-6379.log
26411:M 01 Sep 15:53:18.924 # Server started, Redis version 3.2.11
26411:M 01 Sep 15:53:18.925 * DB loaded from disk: 0.000 seconds
26411:M 01 Sep 15:53:18.925 * The server is now ready to accept connections on port 6379
```
**(prepare all redis service on all nodes, pay attention to the port change)**

### 7.7.2 Cluster configure file 
In the Redis cluster mode, there will be **a log file created automatically** when the node is up first time, this log file is pointed by configure file cluster-config-file. 
The role of cluster configuration files: when the information of nodes in the cluster changes, such as adding nodes, nodes offline, failover, etc. Nodes **automatically save the state of the cluster to the configuration file**. 
The configuration file is **maintained by Redis itself, do not modify it manually** to prevent cluster information from being confused when the node restarts.
```
$ cat nodes-6379.conf
b02fdc78a819fd8c0748009cc9743f9eebd873cf :0 myself,master - 0 0 0 connected
vars currentEpoch 0 lastVoteEpoch 0
```
```
$ 127.0.0.1:6379> cluster nodes
b02fdc78a819fd8c0748009cc9743f9eebd873cf :6379 myself,master - 0 0 0 connected
```
### 7.7.3 Node handshake
A handshake is a process in which a group of nodes running in cluster mode communicate with each other through **Gossip protocol** to sense each other. 
The node handshake is the first step for the cluster to communicate with each other. The command is initiated by the client:
```
				  cluster meet <ip> <port>
```
```
$ 127.0.0.1:6379> cluster meet xx.xx.xx.59 6380
OK
```
```
$ 127.0.0.1:6379> cluster nodes
```
<span style="color:red;">9368b6f104b51353fec0517d84cdbc4493ebdb05 xx.xx.xx.xx:6380 handshake - 1535793291707 0 0 disconnected
b02fdc78a819fd8c0748009cc9743f9eebd873cf :6379 myself,master - 0 0 0 connected</span>

**solution:**
```
$ 127.0.0.1:6379> config set loglevel debug
26411:M 01 Sep 17:42:17.688 . Unable to connect to Cluster Node [xx.xx.xx.60]:16381 -> creating socket: Invalid argument
$ vim redis-6379.conf 
bind 0.0.0.0
$ 127.0.0.1:6379> cluster meet xx.xx.xx.59 6380
OK
```
```
$ 127.0.0.1:6379> cluster nodes
```
b02fdc78a819fd8c0748009cc9743f9eebd873cf xx.xx.xx.58:6379 myself,master - 0 0 0 connected
<span style="color:green;">10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 master - 0 1535796044214 1 connected</span>

<span style="color:green;">We can see the nodes that have already perceived 6380 ports.</span>

**Let all nodes perceived by each other**

```
$ 127.0.0.1:6379> cluster meet xx.xx.xx.60 6381
OK                             xx xx xx
$ 127.0.0.1:6379> cluster meet xx.xx.xx.66 6382
OK                             xx xx xx
$ 127.0.0.1:6379> cluster meet xx.xx.xx.55 6383
OK                             xx xx xx
$ 127.0.0.1:6379> cluster meet xx.xx.xx.56 6384
OK
$ 127.0.0.1:6379> cluster nodes
4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382 master - 0 1535796771989 3 connected
230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381 master - 0 1535796766980 2 connected
9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384 master - 0 1535796767981 5 connected
b02fdc78a819fd8c0748009cc9743f9eebd873cf xx.xx.xx.58:6379 myself,master - 0 0 4 connected
d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383 master - 0 1535796768983 0 connected
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 master - 0 1535796770987 1 connected
```
**All nodes have been perceived, now the six nodes are currently clustered, but they are not working because the cluster node has not yet allocated slots.**

### 7.7.4 Allocate slots
```
$ 127.0.0.1:6379> cluster info
cluster_state:fail
cluster_slots_assigned:0 // The number of allocated slots is 0
cluster_slots_ok:0
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:6
cluster_size:0
cluster_current_epoch:5
cluster_my_epoch:4
cluster_stats_messages_sent:3833
cluster_stats_messages_received:2150
```
```
$ ./redis-cli -h 127.0.0.1 -p 6379 cluster addslots {0..5461}
OK
$ ./redis-cli -h xx.xx.xx.59 -p 6380 cluster addslots {5462..10922}
OK
$ ./redis-cli -h xx.xx.xx.60 -p 6381 cluster addslots {10923..16383}
OK
```
```
$ 127.0.0.1:6379> cluster info
cluster_state:ok // Status of cluster is OK
cluster_slots_assigned:16384 // All slots have been assigned 
cluster_slots_ok:16384
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:6
cluster_size:3
cluster_current_epoch:5
cluster_my_epoch:4
cluster_stats_messages_sent:5356
cluster_stats_messages_received:2858
```
```
$ 127.0.0.1:6379> cluster nodes
4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382 master - 0 1535797388281 3 connected
230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381 master - 0 1535797389281 2 connected 10923-16383
9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384 master - 0 1535797387279 5 connected
b02fdc78a819fd8c0748009cc9743f9eebd873cf xx.xx.xx.58:6379 myself,master - 0 0 4 connected 0-5461
d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383 master - 0 1535797383274 0 connected
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 master - 0 1535797386279 1 connected 5462-10922
```
We can see that at present, there are still three nodes not used, as a complete cluster, each node responsible for processing slots should have a slave node, 
to ensure that when the master node fails, it can automatically fail over. In cluster mode, **the node that is first started and the node that is allocated slot are both master nodes,** 
and the slave node is responsible for replicating the information and related data of the master nodes.
Execute 
```
				cluster replicate <node id> 
```
on slave nodes by cli-command:
```
$ ./redis-cli -h xx.xx.xx.66 -p 6382 cluster replicate b02fdc78a819fd8c0748009cc9743f9eebd873cf
OK                      
$ ./redis-cli -h xx.xx.xx.55 -p 6383 cluster replicate 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8
OK                      
$ ./redis-cli -h xx.xx.xx.56 -p 6384 cluster replicate 230479067a6bf460ca308961c0d2184b35e1223b
OK
$ 127.0.0.1:6379> cluster nodes
4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382 slave b02fdc78a819fd8c0748009cc9743f9eebd873cf 0 1535797621252 4 connected
230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381 master - 0 1535797619749 2 connected 10923-16383
9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384 slave 230479067a6bf460ca308961c0d2184b35e1223b 0 1535797620751 5 connected
b02fdc78a819fd8c0748009cc9743f9eebd873cf xx.xx.xx.58:6379 myself,master - 0 0 4 connected 0-5461
d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383 slave 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 0 1535797621753 1 connected
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 master - 0 1535797616741 1 connected 5462-10922
```
**Now the 3 pairs of master-slave 6-nodes Redis Cluster is completed:**
![2](https://s2.ax1x.com/2019/01/04/FT3pcj.png)
### 7.7.5 Cluster use test
```
$ 127.0.0.1:6379> select 1
(error) ERR SELECT is not allowed in cluster mode
// Multi database space is not supported in Redis cluster
```
```
$ 127.0.0.1:6379> hmset product name 'computer' price '3200' size '14inch'  
(error) MOVED 13865 xx.xx.xx.xx:6381
// Key batch operation support is limited
```
```
$ 127.0.0.1:6379> set test hello
(error) MOVED 6918 xx.xx.xx.xx:6380
// If the slot in which the key is located is not assigned to the current node, the node returns a MOVED error to the client, directs the client to redirect to the correct node
```
```
$ 127.0.0.1:6380> set test hello
OK	
// Clients should send again the command you wanted to execute before on the correct node
```
```
127.0.0.1:6383> dbsize
(integer) 1
$ 127.0.0.1:6383> keys *
1) "test"
$ 127.0.0.1:6383> get test
(error) MOVED 6918 xx.xx.xx.xx:6380
// Slave in cluster does not respond to read request of keys in master, they just replicate keys from master and restore them, like COLD BACKUP
```
```
```
## 7.8 Scalability of Redis Cluster
Redis provides flexible node expansion and contraction schemes. Without affecting the external service of the cluster, 
it is possible to add nodes to the cluster for expansion or to scale offline nodes.
### 7.8.1 Expand Redis Cluster
Cluster expansion is the most common demand for distributed storage.
#### 7.8.1.1 Prepare new nodes
We need two nodes, ports 6385 and 6386, which are basically the same configuration as the previous cluster nodes, 
except for different ports for easy management, refer to 7.7.1 to set these two new nodes on instance xx-xxhadoopdn-01:
```
$ cp redis-6385.conf redis-6386.conf
$ vim redis-6386.conf
:1,$ s/6385/6386/g
wq
$ ./redis-server ../redis-6386.conf &
$ ./redis-cli -p 6386
$ 127.0.0.1:6386> cluster nodes
f56fc18ef1df218cf24dce937e8097b8ab6c9684 :6386 myself,master - 0 0 0 connected
$ ./redis-cli -p 6379
$ 127.0.0.1:6379> cluster nodes
// The new node after startup will run as a stand-alone node without communicating with other nodes.
```
#### 7.8.1.2 Join Redis Cluster
a. Use command <span style="color:red;"> cluster meet (node IP) (port) </span>
```
$ 127.0.0.1:6379> CLUSTER MEET 127.0.0.1 6385
OK
```
b. Use the tool <span style="color:red;"> redis-trib.rb </span>designed for Redis Cluster management
```
$ ./redis-trib.rb add-node 127.0.0.1:6386 127.0.0.1:6379
```
<span style="color:red;"> 
**/usr/local/rvm/rubies/ruby-2.4.1/lib/ruby/site_ruby/2.4.0/rubygems/core_ext/kernel_require.rb:55:in `require': cannot load such file -- redis (LoadError)
	from /usr/local/rvm/rubies/ruby-2.4.1/lib/ruby/site_ruby/2.4.0/rubygems/core_ext/kernel_require.rb:55:in `require'
	from ./redis-trib.rb:25:in `<main>'**
</span>

<span style="color:green;">Solution:</span>
```
$ yum install ruby ruby-devel rubygems rpm-build
$ gem install redis
```
```
$ ./redis-trib.rb add-node 127.0.0.1:6386 127.0.0.1:6379
>>> Adding node 127.0.0.1:6386 to cluster 127.0.0.1:6379
>>> Performing Cluster Check (using node 127.0.0.1:6379)
M: b02fdc78a819fd8c0748009cc9743f9eebd873cf 127.0.0.1:6379
   slots:0-5461 (5462 slots) master
   1 additional replica(s)
S: 4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382
   slots: (0 slots) slave
   replicates b02fdc78a819fd8c0748009cc9743f9eebd873cf
M: 230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381
   slots:10923-16383 (5461 slots) master
   1 additional replica(s)
S: 9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384
   slots: (0 slots) slave
   replicates 230479067a6bf460ca308961c0d2184b35e1223b
S: d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383
   slots: (0 slots) slave
   replicates 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8
M: 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380
   slots:5462-10922 (5461 slots) master
   1 additional replica(s)
```
```
[OK] All nodes agree about slots configuration.
>>> Check for open slots...
>>> Check slots coverage...
[OK] All 16384 slots covered.
>>> Send CLUSTER MEET to node 127.0.0.1:6386 to make it join the cluster.
```
<span style="color:green;">**[OK] New node added correctly.**</span>
```
$ 127.0.0.1:6379> cluster nodes
……
f56fc18ef1df218cf24dce937e8097b8ab6c9684 127.0.0.1:6386 master - 0 1536224128547 0 connected
295515759659c9e2b4d64d885982dd832730a454 127.0.0.1:6385 master - 0 1536224327933 6 connected
……
```
```
$ 127.0.0.1:6379> cluster info 
cluster_state:ok
cluster_slots_assigned:16384
```
The newly joined nodes are all master nodes, since there is no responsible slot, 
they cannot accept any read and write operation requests. For the newly joined nodes, there are two choices of operations:

<span style="color:red;">·Transfer the slot and data for new nodes to achieve cluster expansion.</span>

<span style="color:red;">·Be responsible for failover as the slave of other master node.</span>
#### 7.8.1.3 Migrate slots and data
When we add new nodes to the cluster, we can migrate slots and data to new nodes in two ways, using the <span style="color:red;">redis-trib.rb tool </span>or using <span style="color:red;">manual commands</span>. 
In order to ensure that each master node is responsible for a uniform number of slots, we usually use the <span style="color:red;">redis-trib.rb</span> tool to migrate slots and data in batch. 
The following migration process is shown as using manual commands in a demonstration way.
##### 7.8.1.3.1 Create keys in the same slot
```
$ 127.0.0.1:6379> set key:{test}:111 value:test:111
(error) MOVED 6918 172.16.101.59:6380
$ 127.0.0.1:6380> set key:{test}:111 value:test:111
OK
$ 127.0.0.1:6380> set key:{test}:222 value:test:222
OK
$ 127.0.0.1:6380> set key:{test}:333 value:test:333
OK
$ 127.0.0.1:6380> cluster keyslot key:{test}:111
(integer) 6918
$ 127.0.0.1:6380> cluster keyslot key:{test}:222
(integer) 6918
$ 127.0.0.1:6380> cluster keyslot key:{test}:333
(integer) 6918
$ 127.0.0.1:6380> get key:{test}:111
"value:test:111"
```
We can see that the keys were Originally created in the 6379 node, but redirected to the 6380 node, 
because our common key was allocated to the 6918 slot calculated by the CRC16 algorithm, and the slot was responsible for the 6380 node.
<span style="color:red;">If the key has a {} in its name, the hash value is computed only by the string contained in {}</span>, so the three keys created belong to one same slot.
##### 7.8.1.3.2 Source code of calculating hash value of a key in Redis cluster
```
unsigned int keyHashSlot(char *key, int keylen) {
    int s, e; /* start-end indexes of { and } */
```
<span style="color:red;">// Find the '{' character</span>
```
   for (s = 0; s < keylen; s++)
     if (key[s] == '{') break;
```
<span style="color:red;">// If no '{}' is found, calculating hash value by the whole key</span>
```
if (s == keylen) return crc16(key,keylen) & 0x3FFF;
```
<span style="color:red;">// If find '{', check if also have '}'</span>
```
    for (e = s+1; e < keylen; e++)
        if (key[e] == '}') break;
```
<span style="color:red;">// If not find matched '}'，calculating hash value by the whole key</span>
```
    if (e == keylen || e == s+1) return crc16(key,keylen) & 0x3FFF;
```
<span style="color:red;">// If find matched '{}', calculating hash value by the values in '{}'</span>
```
    return crc16(key+s+1,e-s-1) & 0x3FFF;
}
```
##### 7.8.1.3.3 Migrate keys in slot 6918
a. In <span style="color:red;">target 6385 node</span>, set slot 6918 to <span style="color:red;">import state</span>.
```
$ 127.0.0.1:6385> cluster setslot 6918 importing 
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8
// 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 is the name of node 6380
OK
```
b. In target 6385 node, check state of slot 6918
```
$ 127.0.0.1:6385> cluster nodes
295515759659c9e2b4d64d885982dd832730a454 127.0.0.1:6385 myself,master - 0 0 6 connected [6918-<-10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8
```
c. In source <span style="color:red;">6380 node</span>, set slot 6918 to <span style="color:red;">export state</span>
```
$ 127.0.0.1:6380> cluster setslot 6918 migrating 295515759659c9e2b4d64d885982dd832730a454
OK
// 295515759659c9e2b4d64d885982dd832730a454 is the name of node 6385
```
d. In source node 6380, check state of slot 6918
```
$ 127.0.0.1:6380> cluster nodes
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 172.16.101.59:6380 myself,master - 0 0 1 connected 5462-10922 [6918->-295515759659c9e2b4d64d885982dd832730a454]
```
e. Get keys in slot 6918 in batch 
```
$ 127.0.0.1:6380> cluster getkeysinslot 6918 10
1) "key:{test}:111"
2) "key:{test}:222"
3) "key:{test}:333"
4) "test
```
f. Confirm if these 4 keys are exist in source node 6380
```
$ 127.0.0.1:6380> mget key:{test}:111 key:{test}:222 key:{test}:333 test
1) "value:test:111"
2) "value:test:222"
3) "value:test:333"
4) "hello"
```
g. Migrate by migrate command
```
$ 127.0.0.1:6380> MIGRATE xx.xx.xx.59 6385 "" 0 1000000 keys key:{test}:111 key:{test}:222 key:{test}:333 test
OK
```
f. check if keys still exist in node 6380 
```
$ 127.0.0.1:6380> mget key:{test}:111 key:{test}:222 key:{test}:333 test
(error) ASK 6918 172.16.101.59:6385
```
g. Broadcast new slot info to all nodes in cluster
```
$ 127.0.0.1:6381> CLUSTER SETSLOT 6918 node 295515759659c9e2b4d64d885982dd832730a454
OK
// 295515759659c9e2b4d64d885982dd832730a454 is the name of node 6385
```
h. Check current cluster slot assignment information on node 6379
```
$ 127.0.0.1:6379> cluster nodes
295515759659c9e2b4d64d885982dd832730a454 xx.xx.xx.58:6385 master - 0 1536312693727 6 connected 6918
230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381 master - 0 1536312815088 2 connected 10923-16383
b02fdc78a819fd8c0748009cc9743f9eebd873cf 127.0.0.1:6379 myself,master - 0 0 4 connected 0-5461
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 master - 0 1536312690221 1 connected 5462-6917 6919-10922
```
<span style="color:red;">// As we can see, the slot that the 6380 node is responsible for becomes 5462-6917 6919-10922, 
and 6918 has been responsible for 6385 nodes now.</span>
#### 7.8.1.4 Add new slave node for HA
```
$ 127.0.0.1:6386> CLUSTER REPLICATE 295515759659c9e2b4d64d885982dd832730a454
OK
$ 127.0.0.1:6386> cluster nodes
f56fc18ef1df218cf24dce937e8097b8ab6c9684 172.16.101.58:6386 myself,slave 295515759659c9e2b4d64d885982dd832730a454 0 0 0 connected
```
<span style="color:red;">// Now we have completed the expand of Redis cluster, the new relationship is in the following chart:</span>
![2](https://i.postimg.cc/J0c0FYZ6/image.png)
### 7.8.2 Contract Redis Cluster
Shrinking clusters is a way to reduce the size of the cluster, in order to bring particular nodes offline, two things need to be considered:

Determine whether the downline node is responsible for the slot, if so, need to move the slot to other nodes, 
ensuring the integrity of the whole slot node mapping after the node is offline.

When the offline node is not responsible for the slot or is in the slave node role, 
you can notify other nodes in the cluster to forget the offline node, when all nodes forget the node, it can be closed normally.

In this case, we use <span style="color:red;">redis-trip.rb tool</span> to do the offline and slot migration. 
The whole process is very similar to the expand cluster, but in the opposite direction, 6380 becomes the target node and 6385 becomes the source node. 
Shrink the cluster in the former paragraph.

On node 6379:
```
$ ./redis-trib.rb reshard 127.0.0.1:6385
>>> Performing Cluster Check (using node 127.0.0.1:6385)
M: 295515759659c9e2b4d64d885982dd832730a454 127.0.0.1:6385
   slots:6918 (1 slots) master
   1 additional replica(s)
S: 9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384
   slots: (0 slots) slave
   replicates 230479067a6bf460ca308961c0d2184b35e1223b
S: d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383
   slots: (0 slots) slave
   replicates 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8
M: 230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381
   slots:10923-16383 (5461 slots) master
   1 additional replica(s)
S: 4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382
   slots: (0 slots) slave
   replicates b02fdc78a819fd8c0748009cc9743f9eebd873cf
M: 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380
   slots:5462- 6917 6919-10922 (5460 slots) master
   1 additional replica(s)
M: b02fdc78a819fd8c0748009cc9743f9eebd873cf 127.0.0.1:6379
   slots:0-5461 (5462 slots) master
   1 additional replica(s)
S: f56fc18ef1df218cf24dce937e8097b8ab6c9684 xx.xx.xx.58:6386
   slots: (0 slots) slave
   replicates 295515759659c9e2b4d64d885982dd832730a454
[OK] All nodes agree about slots configuration.
>>> Check for open slots...
>>> Check slots coverage...
[OK] All 16384 slots covered.
```
How many slots do you want to move (from 1 to 16384)? 1

<span style="color:red;">// The number of slots you want to migrate</span> 

What is the receiving node ID? 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8

<span style="color:red;">// The name of the target node (6380)</span> 

Please enter all the source node IDs.

  Type 'all' to use all the nodes as source nodes for the hash slots.
  
  Type 'done' once you entered all the source nodes IDs.
  
Source node #1:295515759659c9e2b4d64d885982dd832730a454

Source node #2:done

<span style="color:red;">// The name of source nodes(6385)</span>
```
Ready to move 1 slots.
  Source nodes:
    M: 295515759659c9e2b4d64d885982dd832730a454 127.0.0.1:6385
   slots: 6918 (1 slots) master
   1 additional replica(s)
  Destination node:
    M: 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380
   slots:5462-6917 6919-10922 (5460 slots) master
   1 additional replica(s)
```
Do you want to proceed with the proposed reshard plan (yes/no)? yes

<span style="color:red;">//Whether the new fragmentation plan implemented immediately</span>

Moving slot 6918 from 127.0.0.1:6385 to 172.16.101.59:6380: ...

Check results on node 6380:
```
$ 127.0.0.1:6380> cluster nodes
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx:6380 myself,master - 0 0 1 connected 5462-10922
295515759659c9e2b4d64d885982dd832730a454 xx.xx.xx:6385 master - 0 1536314238245 6 connected
```
<span style="color:red;">// The 6380 node has taken over the 6918 slot of the 6385 node.</span>

Bring node 6385 and node 6386 offline, pay attention that the slave node is offline firstly, then is the master node, so as to avoid unnecessary full copy operation(failover). 
The rest of the cluster will forget these offline nodes over time.

On node 6379:
```
$ ./redis-trib.rb del-node 127.0.0.1:6379 f56fc18ef1df218cf24dce937e8097b8ab6c9684
>>> Removing node f56fc18ef1df218cf24dce937e8097b8ab6c9684 from cluster 127.0.0.1:6379
>>> Sending CLUSTER FORGET messages to the cluster...
>>> SHUTDOWN the node.
```
<span style="color:red;">// Slave node 6386 first</span>
```
$ ./redis-trib.rb del-node 127.0.0.1:6379 295515759659c9e2b4d64d885982dd832730a454
>>> Removing node 295515759659c9e2b4d64d885982dd832730a454 from cluster 127.0.0.1:6379
>>> Sending CLUSTER FORGET messages to the cluster...
>>> SHUTDOWN the node.
$ 127.0.0.1:6380> cluster nodes
b02fdc78a819fd8c0748009cc9743f9eebd873cf xx.xx.xx.58:6379 master - 0 1536320615393 4 connected 0-5461
4f41b148077474e57081cc54875299a9df8347a8 xx.xx.xx.66:6382 slave b02fdc78a819fd8c0748009cc9743f9eebd873cf 0 1536320613386 4 connected
d3255a7464091afc8d82dcdc954ded95bbc55a1e xx.xx.xx.55:6383 slave 10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 0 1536320614389 1 connected
230479067a6bf460ca308961c0d2184b35e1223b xx.xx.xx.60:6381 master - 0 1536320616396 2 connected 10923-16383
10e2fb1a85a4f5c4105261c9a6b79f2eb4e8ece8 xx.xx.xx.59:6380 myself,master - 0 0 1 connected 5462-10922
9a02ffa11ba46b04202693651be3190a81791073 xx.xx.xx.56:6384 slave 230479067a6bf460ca308961c0d2184b35e1223b 0 1536320612380 5 connected
```
<span style="color:red;">// The offline nodes are safely offline</span>
## 7.9 Conclusion 
Advantages and disadvantages of Redis Cluster:

**advantage**

1. No-central structure.
2. Data are stored in slots and distributed in multiple nodes. Data sharing among nodes can <span style="color:red;">dynamically adjust the data distribution</span>.
3. <span style="color:red;">Scalability</span>, can be extended to 1000 nodes linearly, nodes can be dynamically added or deleted.
4. <span style="color:red;">High availability</span>. Clusters are still available when some nodes are not available. 
By adding Slave as a replica of standby data, failover can be realized automatically. The nodes exchange status information through gossip protocol, and the role of Slave to Master can be promoted by voting mechanism.
5. Reduce operation and maintenance costs, improve the scalability and availability of the system.

**insufficient**

1. <span style="color:red;">The implementation of Client is complex</span>. Driving requires Smart Client, caching slots mapping information and updating it in time, 
which improves the difficulty of development. The immaturity of client affects the stability of business. 
At present, only JedisCluster is relatively mature, the exception handling part is not perfect, such as the common "max redirect exception".
2. The node will be blocked (blocking time is longer than cluster-node-timeout) for some reasons and will be judged offline. This kind of failure is unnecessary.
3. Asynchronous data replication does not guarantee strong consistency of data.
4. When multiple services use the same cluster, they cannot distinguish hot and cold data according to statistics, and the isolation of resources is poor, so they are prone to influence each other.
5. Slave serves as a "cold standby" in the cluster, which does <span style="color:red;">not ease the read pressure</span>. Of course, the utilization of Slave resources can be improved by the reasonable design of SDK.



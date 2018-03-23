---
layout:     post
title:      restoring a snapshot into a new cluster
subtitle:  	use daily backup snapshots to restore into a new Cassandra cluster
date:       2018-03-23
author:     RC
header-img: img/post-bg-cassandra-web.jpg
catalog: true
tags:
    - DBA
    - Cassandra
    - Backup Validity
---

- This is a simple case of Cassandra backup validity test

#### Build a new Cassandra cluster

#### Stop new cluster and clean up related directories
```
# kill -9 $(pgrep -f cassandra)

# cd /usr/local/cassandra/data

# rm -rf ./*

# cd /usr/local/cassandra/commitlog/

# rm -rf ./*

# cd /usr/local/cassandra/saved_caches/

# rm -rf ./*
```
#### Modify cassandra.yaml with new num_tokens and initial_token

* old cluster: node1(256 tokens),node2(256 tokens),node3(256 tokens)

* new cluster: node1(768 tokens)

##### Collect all tokens from old cluster nodes
```
# nodetool ring | grep node1IP | awk '{print $NF ","}' | xargs

# nodetool ring | grep node2IP | awk '{print $NF ","}' | xargs

# nodetool ring | grep node3IP | awk '{print $NF ","}' | xargs
```

##### Modify cassandra.yaml in new cluster
* The total num_tokens in new cluster should be the same with that in the old cluster
(in my case, new cluster only have 1 seed node, so the num_tokens should be set as 
256+256+256= 768)

* The initial_token should be set as the result in step "Collect all tokens from old cluster nodes", please be noted that all numbers should be in one line with no line feeds or carriage returns, and should be separated and end with comma.

#### Restart new cluster and create related keyspaces and tables
```
# cqlsh newnodeip

# CREATE KEYSPACE user_data_store WITH replication = {'class': 'NetworkTopologyStrategy', 'datacenter1': '1'}  AND durable_writes = true;
```
**note that DC name should be that shown by nodetool status**
```
# use user_data_store;

# CREATE TABLE user_item (……)   (desc table table1 on old cluster)
```

#### Stop new cluster and move backup files to related directory
- kill -9 $(pgrep -f cassandra)
- Put all backup files under 
```
/usr/local/cassandra/data/keyspace1/table1/snapshots/full_20180323
```
From old cluster
To:
```
/usr/local/cassandra/data/keyspace1/table1-UUID
```
In new cluster

**Please note that the UUID component of target directory names has changed to new cluster’s.**

* Start new cluster again

#### Verify consistence
```
# cqlsh -ucassandra oldnodeip

# use keyspace1

# select count(1) from table1 limit 9999999;

count 1635229
```
```
# cqlsh newnodeip

# use keyspace1

# select count(1) from table1;

count 1635229
```

#### Reference

You can view this kind of case from official documnet on [datastax](https://docs.datastax.com/en/cassandra/2.1/cassandra/operations/ops_snapshot_restore_new_cluster.html)



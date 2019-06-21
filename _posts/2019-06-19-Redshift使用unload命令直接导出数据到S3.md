---
layout:     post
title:      Redshift使用unload命令直接导出数据到S3
subtitle:  	
date:       2019-06-19
author:     RC
header-img: 
catalog: true
tags:
    - AWS Redshift
    - IAM role 
    - 经验分享
---

### 正文
前几天收到开发的一个需求，从AWS CN的一个redshift cluster里面的表中导出一批较大（将近300W条）的数据到S3上来进行后续debug。

AWS官方提供了一个unload命令，可以在redshift中直接使用将SQL查询的结果直接传到S3上保存，并自带了各种参数满足不同需求：
```
Syntax
UNLOAD ('select-statement')
TO 's3://object-path/name-prefix'
authorization
[ option [ ... ] ]

where option is

{ MANIFEST [ VERBOSE ] 
| HEADER

            
| [ FORMAT [AS] ] CSV
| DELIMITER [ AS ] 'delimiter-char' 
| FIXEDWIDTH [ AS ] 'fixedwidth-spec' }  
| ENCRYPTED
| BZIP2  
| GZIP 
| ZSTD
| ADDQUOTES 
| NULL [ AS ] 'null-string'
| ESCAPE
| ALLOWOVERWRITE
| PARALLEL [ { ON | TRUE } | { OFF | FALSE } ]
| MAXFILESIZE [AS] max-size [ MB | GB ] ]
| REGION [AS] 'aws-region'
```
注意 1.这里的S3逻辑路径后面需要加上上传过去的文件名字的前缀

2.authorization分为一对aws_access_key_id，aws_secret_access_key和IAM role。如果选择IAM role，需要在redshift上添加对应的IAM role，且此
IAM role必须拥有目标bucket的整个读写权限（/*）

3.如果你的bucket里已经有文件存在了，ALLOWOVERWRITE需要加上

4.该命令默认打开PARALLEL，会将整个导出结果平均的分为N个大小相同的文件，每个最大6.2GB，如果指定了MAXFILESIZE，则会以MAXFILESIZE为阈值进行分割

5.更多详细解释参考<https://docs.aws.amazon.com/redshift/latest/dg/r_UNLOAD.html#unload-usage-notes>

实际命令及运行结果：
```
# unload ('select * from XXX where date_id >= 20181201 and app_version in (\'3.0.505.7655-P\',\'3.0.507.7693-P\',\'2.0.8084-P\',\'3.3.103.8704-P\') and event_name in (\'DETECT_HOME_AREA\',\'UPDATE_AREA\',\'UPDATE_SUMMARY\',\'UPDATE_START\',\'ROLLBACK\',\'UPDATE_OK_TO_BOOT\',\'MAP_UPDATE_SUCCESSFULLY_BOOTED\',\'CHECK_UPDATE\',\'CHECK_ENVIRONMENT\',\'DOWNLOAD_DATA\',\'PREPARE_DATA\',\'GET_SPACE_INFO\',\'INITIALIZE\',\'CLEAN_UP\',\'FATAL_ERROR\')')   
to 's3://XXX/XXX_'
iam_role 'arn:aws-cn:iam::XXX:role/Redshift_data_handler_role'
MAXFILESIZE 150MB
GZIP
ALLOWOVERWRITE;
INFO:  UNLOAD completed, 2874727 record(s) unloaded successfully.
UNLOAD
```
查看S3上的文件：
![post-11-1.png](https://i.postimg.cc/5thvpFYD/post-11-1.png)


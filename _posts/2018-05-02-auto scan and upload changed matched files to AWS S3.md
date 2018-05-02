---
layout:     post
title:      Auto Scan and Upload Changed Matched Files to AWS S3
subtitle:  	Locate certain changed files under a Linux directory and upload them to AWS S3 for backup.
date:       2018-05-02
author:     RC
header-img: 
catalog: true
tags:
    - DBA
    - Linux files backup
    - Shell Sctipt
---

### Some special points need pay attention to in the job 

-- How to check AWS S3 upload result --
* Get local file size before upload
```
size1=`du -sb "$diff_file_loacal" | awk '{print $1}'`	
```
* Get AWS S3 file size after upload 
```
size2=`aws s3 ls "$diff_file_s3" | sed '2,$d' | awk '{print $3}'`
```
Please note that aws s3 ls command will show all results fuzzy matching your input filename like:
```
aws s3 ls "s3://xxx/xxx/xxx/test.xml"
2017-05-15 03:50:10       234 test.xml
2017-05-15 03:54:12       1964 test.xml.gz
```
So we only use the first line as unique list result to avoid duplicate results. 
* Compare the two sizes and set upload flag, then update related records in table 

-- How to deal with files with names including spaces --

Sometimes we may meet some filenames including **spaces**:
```
[root@xxx xxx]# ls -ltr /xxx/xxx/
total 764
-rwxr-xr-x 1 xxx xxx 285481 Jan 11 04:44 POI XML Core POIs v5.2.pdf
-rwxr-xr-x 1 xxx xxx 239005 Jan 11 04:44 POI XML General Reference Guide v8.1.pdf
-rwxr-xr-x 1 xxx xxx 251490 Jan 11 04:44 Core POI Australia 171F0 Release Notes.pdf
```
We can solve this by adding ""() to all filename variables like "$diff_file_loacal", "$diff_file_s3"

-- How to deal with files with names including single quotes --

Sometimes we may meet some filenames including **single quotes**:
```
[root@xxx xxx]# ls -ltr /xxx/xxx/
total 1289
/xxx/Disney's-Boardwalk/
/xxx/Kahalu'ua-&-Waiahole
/xxx/Central-&-Leeward-O'ahu
/xxx/Makaha-to-Ka'ena-Point
/xxx/Moloka'i
/xxx/St-John's
```
Filenames of this type cannot insert into MySQL tables directly, you will get an ERROR when remotely calling the MySQL client to write records into a table.

So we should **process the transference part of the single quotes** before put the records into a MySQL table:
```
echo "$line" > ${LOG_PATH}/filer_special_symbol.log
sed -i "s/'/\\\\'\\\/g" ${LOG_PATH}/filer_special_symbol.log
line=`cat ${LOG_PATH}/filer_special_symbol.log`
```






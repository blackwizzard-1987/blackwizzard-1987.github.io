---
layout:     post
title:      AWS RDS for MySQL审计功能开启及审计log收集 下篇
subtitle:  	
date:       2019-10-23
author:     RC
header-img: 
catalog: true
tags:
    - AWS RDS for MySQL
    - Log rotation and collect
    - Boto3 temporary credentials
---

### 正文
#### AWS RDS for MySQL Auditing Log Rotation原理
对于普通的MariaDB Audit Plugin，我们可以在配置选项中看到参数server_audit_file_rotate_now，其默认值为OFF。

如果修改该参数为ON，则触发强制的日志轮转，然而对于AWS RDS，**该参数只能由用户rdsadmin操作，显然是不能更改的**。

因此，当我们enable审计参数之后，RDS会自动进行rotate操作：
```
最新的日志始终是audit/server_audit.log
当server_audit.log的大小到达设定的SERVER_AUDIT_FILE_ROTATE_SIZE值时，触发rotate
即写满的前一个server_audit.log重命名变成server_audit.log.01,然后产生新的server_audit.log
下一个server_audit.log写满时，server_audit.log.01重命名为server_audit.log.02，当前server_audit.log重命名为server_audit.log.01
以此类推，直到到达设定的SERVER_AUDIT_FILE_ROTATIONS（N）个数，
此时，将有server_audit.log，server_audit.log.01，server_audit.log.02，... ，server_audit.log.N 保存在RDS的内部目录/rdsdbdata/log/audit/下
此后，如果server_audit.log再次被写满，则server_audit.log重命名为server_audit.log.01，原来的server_audit.log.01重命名为server_audit.log.02，... ，原来的原来的server_audit.log.29变为原来的server_audit.log.30，原来的server_audit.log.30将被删除
最终以此循环来记录CONNECT,QUERY的event信息
```
该过程用图来表示如下：
![1](https://i.postimg.cc/zBCcskSf/rotate.png)

#### 审计log收集方案·改
在上篇中我们因为不能用access_key和secret_key所以选择了一个折中的缓解方案。

然而，后来在实际部署中我们发现，某些读数据频繁的Instance在一个时间段产生的rotation log非常多，这同样导致丢失掉的log很多，处理起来相当麻烦。

于是，我们开始针对这个log丢失的BUG在不使用access_key，secret_key的前提下询问AWS SUPPORT能否在我们的情景中运用他们提供的Python脚本。

（这里想说一下，AWS的SUPPORT分为WEB，CHAT，PHONE三种，其中WEB和写邮件差不多，可以提供截图之类的信息，并且在24小时内是一定会回复你提的问题的，更重要的是，**只要你不满意，你可以一直回复和对方交流这个问题直到解决为止**）

在我们的穷追猛问下，这位名叫Jack的技术人员提出使用Boto3中的Session库，该库中的get_credentials()函数能根据IAM role生成一个暂时的证书，证书中将包含access_key和secret_key，相关代码如下：
```
from botocore.session import Session
# Get session credentials
    session = Session()
    cred = session.get_credentials()
    access_key = cred.access_key
    secret_key = cred.secret_key
    session_token = cred.token
    if access_key is None or secret_key is None or session_token is None:
        print('Credentials are not available.')
        sys.exit()
```
该方法生成的临时access_key和secret_key在短时间后就会失效，基本符合了我们不使用access_key和secret_key的要求。

通过这个脚本替换掉我之前使用的download-db-log-file-portion命令后，所有audit log的下载都变正常了，没有size变小的log，也不会出现下载不下来的情况。

替换下载命令的脚本代码如下：
```
def aws_version_4_signing(region, instance_name, logfile, oname):
    method = 'GET'
    service = 'rds'
    host = 'rds.' + region + '.amazonaws.com'
    rds_endpoint = 'https://' + host
    uri = '/v13/downloadCompleteLogFile/' + instance_name + '/' + logfile
    endpoint = rds_endpoint + uri
    # Key derivation functions.
    # Taken from https://docs.aws.amazon.com/general/latest/gr/signature-v4-examples.html#signature-v4-examples-python

    def sign(key, msg):
        return hmac.new(key, msg.encode('utf-8'), hashlib.sha256).digest()

    def getSignatureKey(key, dateStamp, regionName, serviceName):
        kDate = sign(('AWS4' + key).encode('utf-8'), dateStamp)
        kRegion = sign(kDate, regionName)
        kService = sign(kRegion, serviceName)
        kSigning = sign(kService, 'aws4_request')
        return kSigning
    # Get session credentials
    session = Session()
    cred = session.get_credentials()
    access_key = cred.access_key
    secret_key = cred.secret_key
    session_token = cred.token
    if access_key is None or secret_key is None or session_token is None:
        print('Credentials are not available.')
        sys.exit()
    # Create a date for headers and the credential string
    t = datetime.datetime.utcnow()
    amzdate = t.strftime('%Y%m%dT%H%M%SZ')  # Format date as YYYYMMDD'T'HHMMSS'Z'
    datestamp = t.strftime('%Y%m%d')  # Date w/o time, used in credential scope
    # Overview:
    # Create a canonical request - https://docs.aws.amazon.com/general/latest/gr/sigv4-create-canonical-request.html
    # Sign the request.
    # Attach headers.
    # Send request
    # Create canonical URI--the part of the URI from domain to query
    canonical_uri = uri
    # Create the canonical headers
    canonical_headers = 'host:' + host + '\n' + 'x-amz-date:' + amzdate + '\n'
    # signed_headers is the list of headers that are being included as part of the signing process.
    signed_headers = 'host;x-amz-date'
    # Using recommended hashing algorithm SHA-256
    algorithm = 'AWS4-HMAC-SHA256'
    credential_scope = datestamp + '/' + region + '/' + service + '/' + 'aws4_request'
    # Canonical query string. All parameters are sent in http header instead in this example so leave this empty.
    canonical_querystring = ''
    # Create payload hash. For GET requests, the payload is an empty string ("").
    payload_hash = hashlib.sha256(''.encode("utf-8")).hexdigest()
    # Create create canonical request
    canonical_request = method + '\n' + canonical_uri + '\n' + canonical_querystring + '\n' + canonical_headers + '\n' + signed_headers + '\n' + payload_hash
    # String to sign
    string_to_sign = algorithm + '\n' + amzdate + '\n' + credential_scope + '\n' + hashlib.sha256(
        canonical_request.encode("utf-8")).hexdigest()
    # Create the signing key
    signing_key = getSignatureKey(secret_key, datestamp, region, service)
    # Sign the string_to_sign using the signing_key
    signature = hmac.new(signing_key, (string_to_sign).encode("utf-8"), hashlib.sha256).hexdigest()
    # Add signed info to the header
    authorization_header = algorithm + ' ' + 'Credential=' + access_key + '/' + credential_scope + ', ' + 'SignedHeaders=' + signed_headers + ', ' + 'Signature=' + signature
    headers = {'Accept-Encoding': 'gzip', 'x-amz-date': amzdate, 'x-amz-security-token': session_token,
               'Authorization': authorization_header}
    # Send the request
    r = requests.get(endpoint, headers=headers, stream=True)
    with open(oname, 'wb') as f:
        for part in r.iter_content(chunk_size=8192):
            f.write(part)
    return str(r.status_code)
    # status_code = 200 is normal
```

至此，整个RDS环境的MySQL审计日志都可以完整的同步到S3上保存了。




---
layout:     post
title:      SQL Server调用存储过程发送邮件
subtitle:  	
date:       2020-03-28
author:     RC
header-img: 
catalog: true
tags:
    - SQL Server
    - 存储过程
    - 邮件
---

## 1.存储过程

使用如下的代码在数据库中创建一个存储过程，通过使用 SQL Server OLE 自动化存储过程调用 CDONTS 对象模型来发送电子邮件。CDONTS 将电子邮件发送到本地 SMTP 虚拟服务器中。该服务器随后将该电子邮件路由到username/password文本框中指定的 SMTP 邮件服务器中，等同于Linux系统中的/etc/mail.rc文件配置。

```html
USE DBA_Monitor
GO

CREATE PROCEDURE Usp_SendDatabaseMail
    @Subject VARCHAR(400) = '' ,
    @HtmlBody VARCHAR(8000) = '' ,
    @AddAttachment VARCHAR(500) = '',
    @UserType VARCHAR(500) = ''
WITH ENCRYPTION
AS
    DECLARE @From VARCHAR(500)       
    DECLARE @object INT    
    DECLARE @hr INT    
    DECLARE @source VARCHAR(255)     
    DECLARE @description VARCHAR(500)     
    DECLARE @output VARCHAR(1000)  
    DECLARE @To VARCHAR(500)
    DECLARE @Cc VARCHAR(500)   

    SELECT  @To = STUFF(( SELECT    ( To_DB_User + ';' )
                          FROM      DBA_DatabaseMailUser
                          WHERE     UserType = @UserType
                                    AND Disabled = 0
                                    AND To_DB_User <> ''
                        FOR
                          XML PATH('')
                        ), 1, 0, '')
    SELECT  @Cc = STUFF(( SELECT    ( CC_DB_User + ';' )
                          FROM      DBA_DatabaseMailUser
                          WHERE     UserType = @UserType
                                    AND Disabled = 0
                                    AND CC_DB_User <> ''
                        FOR
                          XML PATH('')
                        ), 1, 0, '')

    SET @From = 'YourSender@example.com'       
    
    EXEC @hr = sp_OACreate 'CDO.Message', @object OUT    
    EXEC @hr = sp_OASetProperty @object,
        'Configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendusing").Value',
        '2'     
    EXEC @hr = sp_OASetProperty @object,
        'Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpserver").Value',
        'xx.xx.xx.xx' 
	--UserName
    EXEC @hr = sp_oasetproperty @object,
        'configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendusername").value',
        'smtp-auth-user-name' 
	--Password
    EXEC @hr = sp_oasetproperty @object,
        'configuration.fields("http://schemas.microsoft.com/cdo/configuration/sendpassword").value',
        'smtp-auth-password' 	    
    EXEC @hr = sp_OASetProperty @object,
        'Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpserverport").Value',
        '25'     
    EXEC @hr = sp_OASetProperty @object,
        'Configuration.fields("http://schemas.microsoft.com/cdo/configuration/smtpauthenticate").Value',
        '1'    
    EXEC @hr = sp_OAMethod @object, 'Configuration.Fields.Update', NULL     
    EXEC @hr = sp_OASetProperty @object, 'To', @To 
    EXEC @hr = sp_OASetProperty @object, 'Cc', @Cc     
    EXEC @hr = sp_OASetProperty @object, 'From', @From     
    EXEC @hr = sp_OASetProperty @object, 'Subject', @Subject     
    EXEC @hr = sp_OASetProperty @object, 'HtmlBody', @HtmlBody   
    
--add attachment    
    
--send mail    
    EXEC @hr = sp_OAMethod @object, 'Send', NULL     
    IF @hr <> 0
        SELECT  @hr     
    BEGIN     
        EXEC @hr = sp_OAGetErrorInfo NULL, @source OUT, @description OUT     
        IF @hr = 0
            BEGIN     
                SELECT  @output = ' Source: ' + @source     
                PRINT @output     
                SELECT  @output = ' Description: ' + @description     
                PRINT @output     
            END     
        ELSE
            BEGIN     
                PRINT ' sp_OAGetErrorInfo failed.'     
                RETURN     
            END     
    END    
    PRINT 'Send Successfully!!!'     
    
--destroy object    
    EXEC @hr = sp_OADestroy @object    

```

>注意：只有sysadmin服务器角色的成员才可以运行 OLE 自动化存储过程。


## 2.配置表

![1](https://i.postimg.cc/zB3qp2Bj/1.png)

```html
[UserType]:邮件组，这里设定一封邮件只能发送给某个组的成员，比如DBA组（A,B,C三个人），产品组，开发组等
[To_DB_User]：组内成员的邮箱，如xxx@xxx
[CC_DB_User]：与[To_DB_User]相同，但收件人为抄送
[Disabled]：控制收件人（成员）是否有效，0是，1不是
```

## 3.邮件模板

邮件模板同样为一个存储过程，以HTML格式输出邮件内容，最后调用1中存储过程发送邮件，可以设置为作业方便计划任务

```html
DECLARE @RowCAnt INT

DECLARE @Subject VARCHAR(1000)
DECLARE @Content VARCHAR(max)
SET @Subject = '邮件title'

SELECT @RowCAnt = COUNT(1) FROM tabA as A join tabB as B on A.id = B.id  
where colA = 'XXX' and B.CreationTime > convert(varchar(20),getdate(),112)

 IF(@RowCAnt >=1)
 BEGIN
  SET @Content =
   + N'<html>' 
   + N'<style type="text/css">' 
   + N' td {border:solid #9ec9ec;  border-width:1px 1px 1px 1px; padding:4px 0px;}' 
   + N' table {border:1px solid #9ec9ec; width:100%;border-width:0px 0px 0px 0px;text-align:center;font-size:12px}' 
   + N'</style>' 
   + N'<H1 style="color:#FF0000; text-align:center;font-size:14px">' + @Subject + '</H1>' 
   + N'<table >' 
   + N'<tr><td>colA</td><td>colB</td><td>colC</td><td>colD</td><td>colE</td></tr >' 
   + CAST ( ( SELECT 
    td = A.colA , '',
    td = B.colB , '',
    td = colC , '',
    td = colD , '',
    td = colE , '',
FROM tabA as A join tabB as B on A.id = B.id  
where colA = 'XXX' and B.CreationTime > convert(varchar(20),getdate(),112)
   FOR XML PATH('tr') ) AS NVARCHAR(MAX) )
   + N'</table></html>' ;

   EXEC DBA_Monitor.dbo.Usp_SendDatabaseMail @Subject = @Subject, -- varchar(400)
       @HtmlBody = @Content, -- varchar(8000)
       @AddAttachment = '', -- varchar(500)
       @UserType = 'groupA' -- varchar(500)

 END
```

本例中邮件发送条件为若当天存在符合条件的记录，则分别取A和B表的各个字段作为HTML表格的内容，最终发送给groupA的所有成员

## 4.实际邮件效果

![1](https://i.postimg.cc/YSN7p4nJ/2.png)

配合SQL Server代理，可以用来通知/告警/报表等等

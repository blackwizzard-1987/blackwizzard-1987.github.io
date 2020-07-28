---
layout:     post
title:      SQL Server逻辑运算符优先级
subtitle:  	
date:       2020-04-20
author:     RC
header-img: 
catalog: true
tags:
    - MySQL
    - SQL Server
    - SQL
---

## 1.问题由来

同事在SQL Server中执行一个SQL时发现总是无法得到认为的结果，SQL的where条件中使用了and和or的组合

## 2.问题现象

我们用MySQL来模拟一下这个问题，假设该表的内容如下：
![1](https://i.postimg.cc/vmtkg58B/1.png)

查询SQL为：

```html
select * from or_and where num <> 4 or num =3 and num <> 1;
```

结果为：
![1](https://i.postimg.cc/636SdTTh/2.png)

显然与我们想要的满足条件1：**num <> 4 or num =3**
和条件2：**num <> 1**的结果不同

上面的SQL等效为：

```html
select * from or_and where num <> 4  or （num =3 and num <> 1）;
```

这是因为**or的优先级比and低**，在MySQL和SQL Server中均是如此

## 3.解决方法

添加括号将多个小条件合并为一个大的条件

将查询的SQL改为：
```html
select * from or_and where (num <> 4 or num =3) and num <> 1;
```

结果：
![1](https://i.postimg.cc/zv6cZj7d/3.png)

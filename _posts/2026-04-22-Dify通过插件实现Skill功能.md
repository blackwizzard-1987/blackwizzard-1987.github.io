---
layout:     post
title:      Dify通过插件实现Skill功能
subtitle:
date:       2026-04-22
author:     RC
header-img:
catalog: true
tags:
    - Dify
    - Agent Skill
    - 智能体
    - AI应用
---


### 背景

随着智能体对Skill的需求越来越多，Dify在今年2月14日推出了1.14.0-rc1版本支持了Skill功能，但由于该版本仅是前瞻的预发布版本，迟迟没有正式升级。于是偶然间发现早有人在2月初发布了Dify插件支持SkillAgent能力，于是简单尝试了一番，仅作学习记录。

### Skill的思考

在进行操作之前，首先谈下个人对Skill的浅显理解，这部分相信大多数也比较门清了，这里只说几个主要的理解（基于OpenAI理论和anthropics的Skill creator里面的设计思路）：

- Skill主要是**教模型该做什么，怎么做才对**，而不是告诉模型什么是什么

- 作为对比，如果把模型比作员工，**prompt更像是老板的叮嘱**，或者很多话，有可能看前10句还记得，到99句就忘了第一句了

- 针对这种情况，Skill的**渐进式披露**架构设计就很有优越性，完全不用担心模型忘掉重点，而且还有reference来补充大量内容

- Skill的**可复用性**决定了上限非常高，不用挨个给不同场景的Agent传话（改提示词）

- 完全可以把Skill当成是单功能Agent工作流**拆分出提示词和各节点程序**，分别对应Skill.md和scripts的内容

- Skill之所以不像MCP那么传播快，是因为别人的Skill不一定适合你，它本质还是**团队的工程经验、业务经验的沉淀**，如果本身就没有标准的流程、可复用的操作手册，那么Skill也没法建立、使用

### 插件安装后注意问题

插件我们选的Dify市场里面的Skill_Agent。这里简单说下遇到的坑和暂时没解决的东西。

#### 添加技能报错

如果遇到报错：

```html
文件下载失败：unknownurltype/files/23a00abe-029b-4887-966b-eaf5f48927ba/file-preview?timestamp=1774572144&nonce=ad094934257ca23692ed4f45aac03512&sign=0ys
```

需要修改dify项目的**docker路径下面的.env文件**（路径如：xxx\dify-main\dify-main\docker），将FILES_URL和INTERNAL_FILES_URL分别改掉，然后重启docker：

```html
FILES_URL=http://localhost:5001
INTERNAL_FILES_URL=http://api:5001
> docker compose down
> docker compose up -d
```

之后dify便可以将上传的文件读取后给插件使用。

#### 找不到生成结果文件

另一个问题是使用技能后，最终生成的文件无法在前端界面上直接下载的问题。这里暂时没找到解决的办法，只能从docker里面复制出来使用：

```html
-- 找到插件容器id
langgenius/dify-plugin-daemon:0.5.2-local
-- 进入容器，根据agent提供的文件名搜索路径
find / -name 'agent输出文件名'
-- 进入目录，将目标文件全路径记录下来，传回本地
docker cp 你的容器id:/app/storage/cwd/lfenghx/skill_agent-0.0.3@faa24604d1d36cbc6f60dec81eda58564cf79d86dae1472097636ae4b9f017fb/temp/dify-skill-aa0ca008-/result.txt 本地路径
```

#### 技能使用和推荐

测试效果如图所示，不管是自己生成skill这种复杂任务，还是别人写好的通用任务，用ds-v3也可以流畅完成任务：

![1](https://i.postimg.cc/L5wzFkBn/2.png)

![2](https://i.postimg.cc/tJW33SxT/3.png)

> 虽然配色有点丑但该有的都有，也是本地单skill完成的。

这里强烈推荐用下anthropics开源skills仓库里面的**skill-creator**技能，非常专业的生万物能力：[链接](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)


#### 部分局限

有些需要人确定或者反馈的节点（human-in-loop），Agent确实会遵循Skill.md的要求进行问询和确认，但是确认之后**不会像其他本身支持Skill的框架直接继续从刚才的步骤开始任务，而是返回到一开始**，从头开始再看一遍整个Skill内容（这次带了反馈），这样稍微有点影响易用性。

### 小结

通过这个插件成功实现了Dify未来版本可能新增的Skill功能（青春版），虽然比起其他通用智能体或者龙虾类框架还有很多不足，但至少可以用来研究skill，为后面使用提供思路和参考。

### 参考

[插件Github网址](https://github.com/lfenghx/Skill_agent)

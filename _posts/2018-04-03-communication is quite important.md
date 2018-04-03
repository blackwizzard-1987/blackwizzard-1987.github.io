---
layout:     post
title:      communication is quite important
subtitle:  	communication is important all the time, if you ignore it or despise it, you may turn a nice thing into a "extremely bad thing" in a certain situation.
date:       2018-04-03
author:     RC
header-img: img/post-bg-communication-web.jpg
catalog: true
tags:
    - DBA
    - Work Experience
    - Typical Negative Example
---

- This is a typical negative example of bad communication in DBA daily work

### Origin cause
I was arranged to do a backup scripts improvement project by my manager in SH(My company's headquarter is in US, so are the leader of DBA and other staff DBA colleagues) few days ago. I had tested the new scripts in our DEV env and tracked many days longer than 10 to check if it worked well, and the result was good.So I decided to do this change also in our **PROD** environment. 
### Mistaken course
As a matter of routine, I created a RFC(request for change) claiming to do this change, after it was approved, I deployed the new backup script on one of our Cassandra cluster backup servers. In case of failure, I checked the backup result the next day and the result is quite normal. **With a feeling of achivement**, I did the same thing the next day on the second Cassandra cluster backup servers, deploy, check and deploy another until all 3 clusters were modified. Things were all going well at that time, I closed the RFC with the conclusion "the change was done, everything is okay", even didn't realizing I had made a big mistake. 
### Awkward result
Let's see what happened the next week when I come to my office: I received a screaming email from one my colleagues across the Pacific Ocean, asserting that one of our DBA guys in SH must had changed the backup scripts in 3 of our Cassandra cluster backup servers in an irresponsible process, and he, who is the head of our Cassandra database, demanding an immediate roll back for this **illegal** change, and even saying that all these changes didn't involved our largest Cassandra cluster was merciful. I felt like a bolt from the blue when I read this email, did I do something wrong, or did any of the changed server's backup failed? I asked myself, **the answer was No**, because I've tested many times in stage and checked the backup result after I modified the origin script, even did these changes one server by another just in case. 
### Infer and conclusion 
So why my dear colleague was overbearing and judging this is my fault? I soon realized the reason: **I didn't ask him if the change is acceptable for him, even didn't inform him ahead!** I changed the backup notification policy from sending out informing email both success and failure to only send out alert email when something goes wrong in backup process since I'm quite confident that I can handle this thing and had created RFC and my SH manager knew it. But I was totally wrong, this guy who charges our Cassandra database is the **true owner**, I did things out of his control, shocked him and making him felt nervous since he just even didn't knew about this change and seeing "3 of the intended Cassandra backup were gone".Of course all of the backups were okay, but I can't even blame him because **I missed the part of communicating with him, the owner of Cassandra cluster**.Till then I finally realize that **communication is very important, if you ignore it or despise it, you may turn a nice thing into a "extremely bad thing" in a certain situation**, and, a nice thing in work is not just only you think it is, but all of the people related think so. Hope this material for teaching by negative example not only warning myself but also inspiring others.
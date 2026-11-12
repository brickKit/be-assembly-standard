你在装配项目 be-assembly-standard 里。只读文档：组件 crm/opportunity 的设计 components/crm/opportunity/docs/design.md（组件还只有设计），以及它链接或提到的装配项目正式文档 docs/zh/（尤其边界卡 docs/zh/07-components/crm.md、erp-trade.md 的 erp/sales、决定 A71（docs/zh/02-decisions/09-ai-choices.md）、协议 07、02、14、安全 07），和上游组件的设计与 BRICKKIT.md：components/erp/sales、components/mdm/partner 的 docs/design.md 与 BRICKKIT.md，以及这些组件 contract/events/ 下的事件 schema（JSON，算契约文档）。不要读任何代码（.go 文件）。用中文逐题回答，每题写出依据的文件与段落；文档里找不到的，写“文档没写”。不要改任何文件。最后另列一节“文档的空白与矛盾”：你答题时发现文档没说清、互相矛盾、与边界卡或决定不一致、或与 erp/sales 的现状对不上的地方。

1. 商机在 negotiation，用户用两个不同的幂等键各请求了一次报价，第一次的事件被投递了两次。销售会生成几张报价草稿？商机上能看到什么？
2. 装配里没有 erp/sales。用户怎样让商机赢单？此时请求报价会怎样？
3. 部署设置为 order_confirmed。商机的报价被客户接受、转成订单草稿，之后订单确认。商机在哪一刻、以什么金额赢单，操作者是谁？订单币种是 USD 而商机是 CNY 时呢？
4. 商机已赢单，销售人员要把金额改大。怎样做？做完以后商机在哪个阶段、概率多少？
5. 商机在 proposal：(a) 改到 qualification；(b) 改到 proposal；(c) 另一个在 qualification 的商机直接改到 negotiation。各怎样，需要什么？
6. 商机已输单，之后客户接受了同一商机的报价并确认了订单（设置为 order_confirmed）。会怎样？
7. 普通销售张三与销售主管李四：张三看得到谁的商机？他能把自己的商机交给王五吗？漏斗里张三看到的数字怎样算？
8. 新建商机时客户在这个法人下没有开通客户角色，会怎样？法人或币种不存在呢？mdm/currency 不可达呢？
9. 销售收到请求报价，但客户已经不合格（角色被暂停），销售怎样处理，商机怎样知道？销售生成的草稿里没有税率，怎么办？
10. 本组件为什么不把 erp/sales 声明为依赖？销售为什么也不声明本组件？两边怎样找到对方的事件？
11. 客户要把预测改成“按历史赢率”，改哪里？漏斗查询的形状变不变？
12. 整套恢复之后，一个请求在商机上停在 requested，销售那边其实已经有了它的报价草稿。会怎样恢复一致？

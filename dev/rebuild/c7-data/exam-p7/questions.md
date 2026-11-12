你在装配项目 be-assembly-standard 里。这是改动做完之后的一致性检查：读组件 infra/workflow（components/infra/workflow）的文档（docs/design.md、BRICKKIT.md、各层 AGENTS.md、contract/）与代码；erp/purchase（components/erp/purchase）与 erp/payment（components/erp/payment）里与审批有关的文档（docs/design.md、BRICKKIT.md、各层 AGENTS.md）与代码（internal/*/approval.go、internal/policies、入口的 module.go 与它们调用处）；SDK 的流程内核 tools/be-sdk-go/flow 与线协议 tools/be-protocol/spec/17-flow-kernel.md。用中文逐题回答，每题分别写出文档的依据（文件与段落）与代码的依据（文件与函数），再写一行“一致”或“不一致：……”（文档说的与代码做的哪里不同）；两边都没有的，写“没有”。不要改任何文件。

1. 采购：CN01 的政策要审批而没配审批人时提交订单会怎样？政策配了岗位但部署里没有 mdm/employee 呢？配了指定个人呢？政策不要审批时，订单之后能收货吗，凭什么？
2. 采购订单被审批人在待办里驳回：要不要意见，订单变成什么状态、原因从哪来？之后再提交，审批是同一个实例吗？已批准的订单修订、已批准的订单取消、待审批的订单取消，审批实例各变成什么？
3. 同一个员工有两个账号 A、B：A 提交采购申请，B 是岗位持有人。B 能批准吗，答什么？没装员工组件时呢？任务的候选处理人里有没有 B？
4. 审批人用同一个幂等键把“同意”发两次、用不同的键再发一次，各答什么、记下几个决定？原来的 /api/purchase/orders/{id}/approve 路由不带幂等键时呢？
5. 收货（PO07）、验收（PO08）、申请转订单（PR06）在什么时候被放行核对拒绝、答什么原因？依据摘要包含哪些字段？
6. 收付款：付款申请在待审批时被审批人驳回，它在财务的认领何时、怎样释放？已批准未放行的付款申请被驳回呢？取消已放行的呢？
7. 调拨与收付批准即过账：过账用的汇率是何时取的、为什么不在批准时取？审批人驳回时要不要意见？
8. 付款申请的放行人与申请人比较的是账号还是人？没装员工组件时呢？付款政策能不能设成不要审批？
9. 统一待办：一份 erp.purchase_task.changed.v1 由 erp/payment 的服务身份发出、任务类型是采购订单审批，会怎样？以前的发布方再发一份它已有任务的新版本呢？它发一个新任务呢？载荷里的 component 与信封来源不同呢？
10. 统一待办：我的待办、已办、读取一个任务各包括哪些任务、怎样排序？动作入口从哪里来？发布方多久没有心跳与投影时标“可能不是最新”，会不会在本地关闭任务？WORKFLOW_TASK_SOURCES 写错格式会怎样？

# E1 考设计的结果（2026-11-10）

- 考生：两个无头会话（`claude -p --setting-sources project --allowedTools Read,Grep,Glob`），默认模型与 Sonnet；只读文档，题目 `questions.md`，参考答案 `answers.md`（考前写）。
- 结果：两份都 8/8 与参考答案一致（`answer-default.md`、`answer-sonnet.md`）。Sonnet 补出参考答案没写的细节：重放的例外（只有意图且已销毁或擦除时不自动执行、双通道失效列为损失）、岗位退役后已有授予按路径继续匹配（`mdm/org` 的未决问题）。
- 考生标出的“文档没写”：双通道都失效时具体怎样复核（协议 15 只写了严重告警与列入损失）——整套恢复协议的范围，不是员工组件的缺口，不改。
- 结论：设计文档不用改；进 E2。

# 打印渲染引擎的实测（T7.7，2026-10-23）

服务的需求：`infra/print` 在请求里同步渲染一张账单（30 行，中文、西文变音符号与 €），逐字节确定，中文字体嵌入，渲染在隔离的子进程里、有内存上限。

| 项 | Typst（typst-py 0.15.0） | WeasyPrint 70.0（Jinja2 3.1.6 沙箱模板） |
| --- | --- | --- |
| 预热后单张 p50（墙钟 / CPU） | 2.09–2.15 ms / 2.23–2.29 ms | 171–178 ms / 170–177 ms |
| 预热后单张 p95 | 2.6–3.4 ms | 207–216 ms |
| 冷启动（导入加第一张） | 43–45 ms | 557–574 ms |
| 进程内存峰值（`ru_maxrss`） | 81 MiB | 352 MiB |
| PDF 大小 | 83 KB | 192 KB |
| 同进程、跨进程逐字节相同 | 是 | 是 |
| 嵌入的字体（`pdffonts`） | 只有 Noto Sans CJK SC 两个字重 | 只有 Noto Sans CJK SC 两个字重（见下面的注意） |

- 方法：同一份视图模型、两个模板（`invoice.typ`、`invoice.html.j2`），每个引擎一个预热的进程渲染 200 次（Typst）或 40 次（WeasyPrint），三轮交替；性能电源模式（`powerprofilesctl`，跑完恢复原模式）；Python 3.15，12 核 x86-64 笔记本，Linux 7.0。波动：同一引擎三轮的 p50 相差 3%–4%，两者相差约 80 倍。
- 字体：Noto Sans CJK 的 TTC 里取出 SC 一面存成单独的 OTF（`fontTools`），两边都只给这两个文件；WeasyPrint 另给一个只列这个目录的 `fonts.conf`（`FONTCONFIG_FILE`）。
- 注意：WeasyPrint 经 Pango 与 fontconfig 找字体，`@font-face` 指向 TTC 时取第一面（JP 的字形），缺字时回退到系统字体（第一次实测嵌入了系统的 Noto Sans 与 Noto Serif），要靠镜像里只有指定字体才封闭；Typst 用 `font_paths` 加 `ignore_system_fonts=True` 自己就封闭，只有它内置的 Libertinus 等字体作最后的回退（字体名写错时会用到）。
- 结论：选 Typst。快约 80 倍、内存约四分之一、自己封闭（不读系统字体、不能访问网络，只读给定根目录下的文件），确定性同样成立；代价是模板不是 HTML。
- 何时复测：Typst 或 WeasyPrint 大版本更新；单据变成几十页以上；客户要求以 HTML 改模板。

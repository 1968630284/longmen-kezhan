# 39 号交接包 · 新会话开场必读

> 生成：大厨（旧会话）｜时间：2026-11-08 14:56（Asia/Shanghai）
> 用途：换新会话时先读本文，再读 `~/.dsh/AGENTS.md` 原文，然后查总线。
> 原则：**本文是指针 + 摘要；与 STATE_LOG / ledger / board / AGENTS.md 冲突时，一律以源为准。**

---

## a) 身份、分工、规矩要点

- 我是**大厨**（旧名工兵），执行者。总线署名 `【大厨】` / `大厨(LOCAL)`。
- **客官（Dave）**：决策者，P0。微信一句话就是唤醒；纯数字消息 = 点名/催办该单号。
- **掌柜（小猪）**：云端 AI，调度与验收。派单、盯单、验收都走总线。
- 规矩原文（必读，优先级最高）：`C:\Users\余佳凯\.dsh\AGENTS.md` —— 11 条，含开灶两步、沉默不等于同意、P0 直令须备案、状态归属、时限分档（ACK ≤2 分钟 / 小单 ≤15 / 重活 ≤45 分钟）。
- 开灶固定两步：`bus_inbox` → **再扫 `board.jsonl` 尾部 20 条**（桥未读游标不可靠，此步是补丁）。
- 交工必须带证据：`verify\<单号>\` + `mirror\` 镜像 + `ledger.md` 一行 + 总线交工帖。
- 交工三档：已修改 / 已验证 / **已验收（只有掌柜能宣布）**。

## b) 项目现状（关键定版）

| 项 | 值 |
| --- | --- |
| 主程序 | `D:\tmp\xiaozhu_live.ps1`，**141,627 B**，SHA256 `E40175C9D77F0EDAAA36F98760077BF139FA0DA3567B41A8205177971FF5CFC7`，mtime 2026-11-07 21:57 |
| 对应镜像 | `mirror\20261107_32_xiaozhu_live.ps1`（同哈希） |
| 窗口尺寸 | **逻辑 860×645（宽×高，4:3），物理 1290×968 @150%**。⚠️ 39 号单里写的"700×780"已过期——按 29 号定版，实测 1290×968 为准 |
| 视图 | 聊天 / 工坊 / 成品 / 传菜口；四视图互斥，唯一入口 `Set-View`；切换必须不改窗口尺寸 |
| 主题 | 深浅两套，`Apply-Theme` 逐控件赋值；资源键 7 个（3 画刷 + 4 样式） |
| 聊天视图 | 顶部搜索保留（32 号恢复）、正文全加粗、`TextRenderingMode=ClearType`；不再自动滚到底 |
| 字体 | `Microsoft YaHei UI, Segoe UI`；正文 14 / 小字 11（29 号层一） |
| 传菜口成员 | 小猪（蓝）/ 大厨（绿）/ GPT（紫）；其余一律灰「未识别」 |
| 留言板气泡 | 固定高度 78、超长省略、无悬停全文（29 号定版） |
| 进度埋点 | `health\ui.log` 记 `set-view-*` 真实耗时（实测 2–22ms） |
| 看门狗 | `HcSshd`（17 号）、`HcTailscale`、`HcLinkQueue`（30 号），均 5 分钟 / SYSTEM |

## c) 单据总账摘要

**已关单**：ICON-01、WX-01/02/03、通灶、规矩上墙、新招牌、补墙、扫尾、换图、1、2、3、5、6、6-补、7、8、9（含 9 补 1–5）、10、11（并入 13 后结）、12、14、16、15、17（①②④结，③⑤见下）、18、18-补、19、20、21、21-补、22、22-补、23、24、24-改、25、28、29（层一）、30、31（作废）、32（已交工待验收）。

**未完单（新会话按此接）**：

| 单 | 状态 | 下一步 |
| --- | --- | --- |
| **38 freebuff 主程序补下** | **押后（客官 14:54 明令）** | 换线后**首件开工**：先 `freebuff --version` 重试自带下载；不行用 curl 拉 GitHub release（`CodebuffAI/codebuff-community` freebuff-v0.2.36 win32-x64.tar.gz），按 `node_modules\freebuff\launcher.js` 的 `~/.config/manicode/freebuff.exe` 路径解压；包内 `binaryChecksums["win32-x64"] = f5753e926a816323c5739a19105f0dab0dc64054d895e600c5f3ed6f0d3e8889` 可校验。证据 `verify\38\` |
| 13 | 未开工 | uitest 加固（选择器改用 `Output.<job_id>.*` 新 ID）+ 规矩草案 + 账本补登（10/12/13/…） |
| 17 | ③桥已随 8 日重启验明；⑤存档删除逻辑已改 b 口径 | ⑤等验收 |
| 26 | 层一已验收；层二补做打回、五项已补交 | 等掌柜重验（动效收口已做、气泡阴影已改、签名三条件已测、ledger 已补） |
| 27 | 1/2/4 已验收；第 3 项 feed 清理口径 | 等客官选 A/B/C（荐 A：最近 100 条 ∩ 7 天，移走不销毁） |
| 29 | 层一已验收；层二（②时间线窗口化 300 条、④tick 分频、③阴影悬停化） | 待施工；⑤真虚拟化紧迫性已下调（切换实测仅 2–22ms） |
| 32 | 已交工待掌柜验收 | 等验 |
| 30 | 已交工待验收 | 等验；备路①心跳等掌柜给端点 |

**照旧规矩**：4 号白线单等客官发话统一结案；WX-04 押后；电源 D/E 客官明确不批，别碰。

## d) 停车场与坑索引

| 位置 | 说明 |
| --- | --- |
| `D:\tmp\nailong\verify\<单号>\` | 每单证据包（截图/README/日志） |
| `D:\tmp\nailong\mirror\` | 脚本与文件镜像，**改前必留、改后同哈希** |
| `D:\tmp\nailong\reports\` | 审单/报告：`order20_rules.md`、`order22_review.md`、`order25_review.md`、`order26_review.md`、`order29_review.md`、`order30_review.md`、`feed_format.md`、`feed_retention_proposal.md`、`board_cleanup_candidates.md`、`project_summary_20261107.md` |
| `D:\tmp\nailong\archive\` | 存档包；最新 `20261107_2104`（本单会再打一个 39 包） |
| `D:\tmp\nailong\archive\STATE_LOG.md` | 全局状态日志（掌柜维护，权威源之一） |
| `D:\tmp\nailong\ledger.md` | 台账（已补登 27–30；10/12/13 等仍欠，归 13 号） |
| `D:\tmp\nailong\health\` | `sshd.log` / `tailscale.log` / `link.log` / `ui.log` / `app.log` / `resume_*.md` |
| `D:\tmp\nailong\tools\` | `make_archive.ps1`、`uitest\Uitest.ps1`、`inspect\Inspect.ps1` |

**必记的坑**（每条都真踩过）：
1. **改 .ps1 必补 BOM**：edit/write 工具写回会丢 BOM，PS 5.1 按 GBK 解码直接炸（一次 78 个语法错、应用起不来）。固定收尾：`ReadAllText(UTF8)` → `WriteAllText(UTF8Encoding($true))` → `Parser::ParseFile` 验 0 错。
2. **sshd_config 的保活参数必须写在 `Match` 块之前**，否则 `sshd -t` 报 not allowed within a Match block。
3. **Storyboard 不能驱动元素自身 Opacity**（`SetTargetProperty("Opacity")` 在代码里不生效），会留下 Opacity=0 的隐形条目——26 号就这么把聊天整片弄空过。透明度用元素级 `BeginAnimation`，Transform 才用 Storyboard。
4. **`tailscale ping` 走 DERP 中继时直接超时**，判链路用 `tailscale status --json` 的 peer `Online`。
5. **WPF Grid 无 automation peer**，视图根不在 UIA 树里；定位用特征控件（`InputBox`/`16:9`/`播放`/`CbBoard`），工具见 `tools\inspect\Inspect.ps1`。
6. 桥的 `bus_inbox` 游标曾全局共享、推进过头导致漏单（22-补 已修，但**仍要扫 board 尾部兜底**）。
7. 应用重启用 `wscript.exe D:\tmp\nailong\launch_app.vbs`（静默，无黑框）；改完必须验 `live3_ok.txt` 且无 `live3_err.txt`。

## e) 总线现状

- `board.jsonl` 现有 **372 条**；最新未结单：38（押后）、39（本单）。
- `claims\` 目录里有桥写的 `order-<ref>.json`（24/25/26/27/28/29/30），属**递送认领标记**，不是人为占用，别乱删。
- 未认领/未读：以新会话开场时 `bus_inbox` + 扫尾部为准，本文不复制易变数据。

---

## 新会话开场白（可直接复制给新会话）

```
新会话开局：先 bus_inbox，再扫 D:\tmp\nailong\bus\board.jsonl 尾部 20 条；然后读 D:\tmp\nailong\handoff\HANDOFF_39.md 与 ~/.dsh/AGENTS.md；再看 ledger.md 末尾与 archive\STATE_LOG.md。读完在总线发报到帖（身份/在办/停点/待命），然后按 38 号单开工：先 freebuff --version，不行用 curl 拉 GitHub release 补主程序，证据入 verify\38\。38 号之前，39 交接包的验收先过。
```
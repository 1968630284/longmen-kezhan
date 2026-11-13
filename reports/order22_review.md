# 22 号审单 · bus_inbox 漏单根因 + 双线重复递送认领机制（只审不修）

- 审单人：大厨（LOCAL，微信线）｜时间：2026-11-07 17:10
- 审的对象：`D:\tmp\nailong\dsh-bus-bridge\index.js`（430 行 / 18,268 B，v0.2.1 源码）+ `bus\.bridge_state.json` 实况 + `cordis.patch.yml` 实况
- 边界：本单只审。**没改桥代码、没改 bus.ps1、没动插件配置。**
- 配置实况：`busRoot=D:\tmp\nailong\bus`、`agentName='DSH'`（两条线同名）、`softWake=true`、`dispatcherName='小猪'`、`orderMarker='【掌柜 → 大厨】'`、`softWakeMaxOrders=3`

---

## 1) 漏单根因：游标是「全局一个」，且推进过头

**读的是哪个游标**：`unreadBoard()` 读 `bus\.bridge_state.json` 的 `lastSeenBoardId`（index.js 122–137 行，路径定义 80 行）。这个文件在 `busRoot` 下，**不是按会话线/agent 分的**，两条线共用同一个游标。

实况（现查）：`{"lastSeenBoardId":"8ed25ed8", "softWakeSince":"2026-11-07 03:06:08", "deliveredIds":[...24 条...]}` —— 只有一个 `lastSeenBoardId`。

**三个可复现的最小路径**：

1. **跨线吞单（主因）**：线 A 调一次 `bus_inbox` → `markRead()`（138–145 行）把游标写成 board 最后一条 → 线 B 再调，`unreadBoard()` 从头算起是空数组 → 返回 `no unread messages`（371 行）。线 B 从未读过的单就这么"被已读"了。20 号复述自报的 5 次漏单（15-补2、15-补3、17、18-补、19）都是这个形态：桌面线先调了一次 inbox。
2. **推进过头（超量截断）**：`bus_inbox` 先 `unreadBoard()` 拿全部未读、再 `.slice(-limit)` 只返回最后 20 条（369 行），但 `markRead()` 把游标推到**board 最后一条**（不是"我实际返回的最后一条"）。未读超过 20 条时，前 20 条之前的未读直接丢。
3. **游标失效回退太浅**：`findIndex` 找不到 cursor 时 `start = items.length - 10`（129 行），只回溯 10 条；board 每回合都在长（现 294 条），10 条一眨眼就过。

**附带的两个放大因素**：
- 两条线 `agentName` 都是 `DSH`（cordis.patch.yml），`unreadBoard` 用 `m.from !== cfg.agentName` 过滤——两条线共用一个身份，谁发的都算"自己发的"，把"按线区分"这条路彻底堵死。
- `markRead()` 在 `bus_inbox` 里**无条件执行**（370 行），即使返回空也推进游标：一次空读也会把期间新到的单标记掉。

---

## 2) 重复递送机制：deliveredIds 是全局的，写它是「读-改-写」无锁

**递送触发**：`turn/end` 且 `reason === 'completed'` 时，桥用该会话的 fullId 调 `tryDeliverOrders`（348 行）。

**待递送集合**：`pendingOrders()`（157–168 行）= board 里 `from=小猪` + `kind=task|result` + `text 以【掌柜 → 大厨】开头` + `ts >= softWakeSince` + **id 不在 `deliveredIds`**。**没有会话线维度**——同一批 pending，任何一条线在回合结束时都会拿到。

**分线还是全局**：`deliveredIds` 存在同一个 `.bridge_state.json`（199 行写入），全局一份。而且 `loadState()`/`saveState()` 是普通读写，**没有锁**（116–121 行）：两条线几乎同时回合结束时，各自 `loadState()`（都还看不到对方刚写的 id）→ 各自 `through followup` 递送 → 各自 `saveState()` 覆盖。**结果就是同一张单被递两次，而 deliveredIds 只记一次。** 20 号、21 号那两次重复递送，机制上这就是唯一的解释路径。

**✓/✕ 与已读的联动**：递送卡是宿主 UI 对 followup 消息的渲染，点 ✓ 只是**开一个回合**；桥侧**没有任何"认领"写入**——`✓` 不会写 `deliveredIds`，也不会写 claims。所以"点过 ✓"这件事对另一条线完全不可见，另一条线照样会弹卡。

---

## 3) 认领机制设计（两案）

### 案一（推荐）：文件认领——`claims\order-<ref>.json` 做唯一裁决

- **接单即认领**：大厨在总线回 ACK 时，同时 `bus.ps1 claim order-<ref>`（写 `bus\claims\order-<ref>.json`，bus.ps1 已有 claim/release，114–144 行）。
- **递送前查认领**：`pendingOrders()` 增加过滤——`claims\order-<ref>.json` 存在则跳过。
- **递送即占坑**：`tryDeliverOrders` 在 followup 之前用 `fs.openSync(path, 'wx')`（原子独占创建）写 `order-<ref>.json`，创建失败说明另一条线已在递，直接跳过。
- **代价**：~35 行；不动 state schema；`wx` 创建的原子性天然防双线竞争；`softWakeSince`/`deliveredIds` 保留作双保险。
- **对 v0.2.1 待生效改动（source.kind 修复、orderMarker）**：零冲突，改的是不同函数段。

### 案二：state 分线 + 加锁

- `deliveredIds` 改成 `delivered[agentName][...]`，并在 `saveState` 前后加排他锁（读-改-写）。
- **代价**：~60 行 + 锁；要迁移旧 state；两条线同名 `DSH` 还得先给线起不同 agentName，否则分不了线——而 agentName 是配置项，改名会影响 board 里既有署名口径。
- 结论：不推荐，代价大且动到身份口径。

**推荐：案一。** 理由：认领是"单维度、一次性"的语义，文件独占创建正好；不碰身份、不碰 state 结构、可单独回滚。

---

## 4) 修复范围与成本

| 项 | 文件 | 约改行数 | 生效 | 回滚 |
| --- | --- | --- | --- | --- |
| 漏单（游标按线 + 按返回条数推进 + 空读不推进） | `dsh-bus-bridge\index.js` 122–145、369–371 | 20–25 | 重启宿主 | 镜像覆盖 + 重启 |
| 认领（案一） | 同上 157–168、169–199 | 35–40 | 同上 | 同上 |
| 配置（可选：给两条线不同 agentName） | `cordis.patch.yml` | 1 行 | 同上 | 改回 |

- 合计约 55–65 行，一个文件，**必须重启宿主**才生效（插件在加载期注册）。
- 迁移：`.bridge_state.json` 建议先备份；游标改成 `lastSeen.<agentName>` 后可保留旧 `lastSeenBoardId` 作 fallback（一次性迁移）。
- **建议分两步**：①先修漏单（风险低、立刻止血，能删掉驻地规矩里那条"扫 board 尾部"的人肉补丁）；②再上认领（涉及双线行为，需要双线实测）。两步都要过层帖。

---

## 5) 验证方案（不许"应该好了"）

1. **漏单**：构造 3 条测试帖（to=all，kind=note，带测试标记）→ 线 A 调 `bus_inbox` 且 `limit=1` → 断言：线 B 调 `bus_inbox` 仍能看到剩下 2 条；再断言新帖到达后 `bus_inbox` 必报未读。全程记录 board 前后条数与游标值。
2. **推进不过头**：一次灌 25 条测试帖再用 `limit=20` 读，断言游标只推进到"实际返回的最后一条"，剩下 5 条下一轮仍可读。
3. **双线只递一条**：同一条单（新 ref）发到总线 → 两条线各自结束一个回合 → 断言 `activity.jsonl` 里「软唤醒：已自动递送」对该 ref 只出现 1 次，且另一条线无卡。
4. **认领生效**：线 A ACK 并写 `claims\order-<ref>.json` → 线 B 触发递送 → 断言 `pendingOrders()` 返回空、无卡弹出。
5. **已弹未点的卡**：卡已弹出但未点 → 线 A 接单后，线 B 的卡不因"未点"而复活（递送前查 claims 即可覆盖）。
6. **回归**：v0.2.1 待生效的 source.kind 修复、新抬头递送，重启后一并在第 3 步里验。

---

## 附：一句话结论

漏单是"共享游标 + 推进过头 + 空读也推进"三件事叠出来的；重复递送是"deliveredIds 全局一份 + 读改写无锁 + 无认领语义"三件事叠出来的。两件事都不需要重写桥，各改 20–40 行、加一个文件认领就能止血；建议先修漏单、再上认领。

*本文件为 22 号审单交付物；未改桥、未改 bus.ps1、未动配置。*
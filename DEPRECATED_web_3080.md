# 3080 web 宿主 · 已报废（DECOMMISSIONED）

报废时间：2026-11-07 15:33（Asia/Shanghai）
依据：17 号单，客官 15:33 微信裁决「报废」（选项 B）。

## 现状

- 计划任务 `NailongDSHWeb` **已删除**（导出备份见 `D:\tmp\nailong\verify\17\decommission\NailongDSHWeb.xml`）。
- 3080 端口无监听，无相关进程。
- 启动器 `start_web_host.cmd`、日志 `web_host_log.txt` 原件保留（只读留档，不再被任何东西调用），备份在 `verify\17\decommission\`。

## 为什么报废（实查结论）

- 该任务的触发器列表**是空的**——只在手动 `Start-ScheduledTask` 时跑一次，重启后不会自启。所以"倒掉之后永远不会自己回来"，这才是「今晨起就是倒的」的真因，不是崩溃。
- 日志末尾停在 `dsh web: http://127.0.0.1:3080/?token=…`，之后没有错误行，属正常退出或被结束，无崩溃证据。
- 依赖检查：桌面线、微信线都跑在桌面 profile，不经过 3080；微信桥插件在各自宿主内加载。报废不影响这两条线，也不影响总线桥的 `bus_inbox`/`bus_post`（那两个工具由当前会话所在宿主提供）。

## 若将来要复活（回滚）

1. 导入 `verify\17\decommission\NailongDSHWeb.xml`（`Register-ScheduledTask -Xml (Get-Content ...) -TaskName NailongDSHWeb`）。
2. 或直接手动跑 `D:\tmp\nailong\start_web_host.cmd`。
3. 回滚前想清楚：触发器为空是原设计缺陷，复活时应补一个「登录时启动」的触发器，否则还是倒一次就永久躺平。

**别再凭印象重建这个任务。**
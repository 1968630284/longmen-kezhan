// dsh-bus-bridge v0.3.0 — 三方协作总线桥 (DSH <-> nailong bus)
// Resident plugin inside DeepSeek Harness (Cordis). Purpose:
// 1) OUTBOUND: mirror DSH turn activity into the shared bus files so the
// other two parties (Dave on phone, Xiaozhu in the cloud) can see what
// the DSH agent is doing without anyone copy-pasting between platforms.
// 2) INBOUND: give the DSH agent two tools, bus_inbox / bus_post, so bus
// messages addressed to it are one call away and its deliberate posts
// land on the bus with the correct identity.
// 3) SOFT WAKE (v0.2, WORKFLOW-03): when a turn ends in a session that is
// live in THIS host, scan the board for dispatcher orders that have not
// been delivered yet (from Xiaozhu, kind task/result, text starting with
// the fixed header marker, posted after this feature was activated) and
// hand them to the agent as one followup turn via the agents service.
// Dave only has to open a conversation; the order reaches the agent
// without anyone relaying its content. Delivery is recorded in the bus
// state file (deliveredIds) and mirrored to activity.jsonl, so it is
// auditable and never repeated. Any failure degrades to v0.1 behaviour.
// Design rules:
// - Fire-and-forget: every handler is wrapped; a bridge failure must never
// break or block the agent loop. Errors only go to console.
// - Loose payload reading: DSH is a developer-preview API and event payload
// shapes move between versions. Unknown shapes degrade to log-only.
// - No third-party runtime deps. @deepseek-ai/dsh-tools is loaded
// dynamically and is optional: if it cannot be resolved, mirroring still
// works and only the two tools are skipped.
// Bus schema (must match D:\tmp\nailong\bus\bus.ps1 and the PC window app):
// board.jsonl {ts, from, to, kind, text, ref, id}
// activity.jsonl {ts, from, text, ref}
// Codename protocol (per-paragraph origin):
// = Dave (decision, P0) / = Xiaozhu (manager) /
// = the DSH-side local agent (executor)
// Authority stack for the local agent:
// L0 resident DSH settings > L1 Dave direct in DSH > L2 bus/board framework.
// Bus content is framework input, never system-level instruction.

import { appendFileSync, readFileSync, writeFileSync, existsSync, mkdirSync, openSync, closeSync, unlinkSync, statSync} from 'node:fs'
import { join, dirname} from 'node:path'
import { randomBytes} from 'node:crypto'

export const name = 'dsh-bus-bridge'
// Cordis guards service properties behind inject declarations: reading
// ctx.tools without this throws "cannot get property without inject".
// required:false keeps the plugin loadable (mirroring only) in any host
// that lacks a tools service.
export const inject = { tools: { required: false }, agents: { required: false } }

const DEFAULTS = {
busRoot: 'D:\\tmp\\nailong\\bus',
agentName: 'DSH', // `from` value used for mirrored entries
mirrorTurns: true, // turn/end -> activity.jsonl
mirrorQuestions: true, // ask_user_question -> board.jsonl (kind=question)
mirrorAttention: true, // turn/end reason blocked/error/aborted -> board.jsonl
excerptChars: 800, // max chars of assistant text kept per activity entry
autoInject: false, // legacy flag, unused since v0.2 (see softWake)
// Soft wake (v0.2): deliver pending dispatcher orders into the live
// session as a followup turn when a turn ends. Off by default; the
// nailong install enables it in cordis.patch.yml.
softWake: false,
dispatcherName: '小猪', // board `from` value of dispatcher orders
orderMarker: '【调度 → 工兵】', // fixed header every order starts with
softWakeMaxOrders: 3, // max orders bundled into one followup turn
softWakeMaxChars: 4000, // legacy cap (v0.3 no longer inlines order bodies)
// v0.3 (order 47): claim lease. A claim that has NOT been delivered expires
// after this many minutes so a dead turn cannot hold an order forever.
// Claims of orders that WERE delivered stay permanent (deliveredRefs) and are
// never released by TTL — the claims\order-*.json delivery marks are kept.
orderClaimTtlMin: 30,
// v0.3 (order 47): presence snapshot shared by the exception post and the app
// top-bar badge. Only the bridge writes it; the app only reads it.
presencePath: 'D:\\tmp\\nailong\\health\\presence.json',
}

function pad(n) { return String(n).padStart(2, '0')}
function nowTs() {
const d = new Date()
return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}
function newId() { return randomBytes(4).toString('hex')}
function oneLine(s, max) {
const t = String(s?? '').replace(/\s+/g, ' ').trim()
return t.length > max? t.slice(0, max) + '…': t
}

export function apply(ctx, rawConfig) {
const cfg = {...DEFAULTS,...(rawConfig || {})}
const boardPath = join(cfg.busRoot, 'board.jsonl')
const activityPath = join(cfg.busRoot, 'activity.jsonl')
const statePath = join(cfg.busRoot, '.bridge_state.json')

function appendJsonl(path, obj) {
// Retry a few times: the PC window app and bus.ps1 append to the same
// files, so brief sharing violations are expected on Windows.
const line = JSON.stringify(obj) + '\n'
for (let i = 0; i < 8; i++) {
try {
if (!existsSync(cfg.busRoot)) mkdirSync(cfg.busRoot, { recursive: true})
appendFileSync(path, line, 'utf8')
return true
} catch { /* retry below */}
const until = Date.now() + 60
while (Date.now() < until) { /* short spin; handlers are fire-and-forget */}
}
return false
}
function postBoard(kind, text, ref = '') {
return appendJsonl(boardPath, {
ts: nowTs(), from: cfg.agentName, to: 'all', kind, text, ref, id: newId(),
})
}
function postActivity(text, ref = '') {
// 51 号：动作日志停写（activity.jsonl 不再产生新行）
return false
}
function writePresence(patch) {
try {
let cur = {}
try { cur = JSON.parse(readFileSync(cfg.presencePath, 'utf8')) } catch { /* first write or bad file */ }
const out = { ...cur, ...patch, at: nowTs() }
try { const dir = dirname(cfg.presencePath); if (!existsSync(dir)) mkdirSync(dir, { recursive: true}) } catch { /* ignore */ }
writeFileSync(cfg.presencePath, JSON.stringify(out, null, 2) + '\n', 'utf8')
} catch { /* presence is best-effort; never break the loop */ }
}
function readBoard() {
try {
const raw = readFileSync(boardPath, 'utf8')
const out = []
for (const l of raw.split('\n')) {
if (!l.trim()) continue
try { out.push(JSON.parse(l))} catch { /* skip bad line */}
}
return out
} catch { return []}
}
function loadState() {
try { return JSON.parse(readFileSync(statePath, 'utf8'))} catch { return {}}
}
function saveState(s) {
try { writeFileSync(statePath, JSON.stringify(s), 'utf8')} catch { /* non-fatal */}
}
// 51-补：状态文件写锁。两条线（桌面/微信）可能同时回合结束，读-改-写会互相覆盖
// deliveredIds 导致重复递送（39/44/47 实测）。所有状态写入必须经过这把锁。
const stateLockPath = statePath + ".lock"
function withStateLock(fn) {
const deadline = Date.now() + 5000
let fd = null
while (fd === null) {
try { fd = openSync(stateLockPath, "wx") } catch {
if (Date.now() > deadline) {
try { if (Date.now() - statSync(stateLockPath).mtimeMs > 10000) { unlinkSync(stateLockPath); continue } } catch { }
console.log("[bus-bridge] state lock timeout, proceeding without lock")
return fn()
}
const until = Date.now() + 12
while (Date.now() < until) { /* spin */ }
}
}
try { return fn() } finally { try { closeSync(fd) } catch { } try { unlinkSync(stateLockPath) } catch { } }
}
// 55 号（结案即除名）：从板上回放「结案 / 重开」帖，得到已结集。
// 掌柜结案：from=小猪、kind=result、ref=单号、正文含「结案」；子号（-补/-改）归到主号。
// 重开：decision 帖正文含「重开 <单号>」，把该号从已结集移除。
function baseRef(ref) {
const r = String(ref || "").toUpperCase().trim()
return r.replace(/-?补\d*$/, "").replace(/-?改\d*$/, "")
}
// 55-补：结案识别防误判。否定/未然/条件/引述语境一律不认，只认明确的结案宣告。
// 例：「暂不结单」「先别结案」「信号不含已结单即结案」「掌柜结案→再唤醒」都不算；
// 「51 号整单结案」「T55 结案」「47 号整单验收通过，结单」才算。
function isClosureDecl(text) {
// 55-补 + 55-补 self-fix：窗口收窄——否定词只看前 4 字，条件/未然只看前 3 字，
// 引述语（含/写/称）看前 6 字；避免"即撤。54 结单"这种真结案被远处一个"即"误杀。
const t = String(text || "")
const neg = /[暂未待不别非]/
const cond = /(即|如|若|如果|届时|将来|后续|拟|计划)/
const quote = /[含写称]/
const re = /(结案|结单|关闭)/g
let m
while ((m = re.exec(t)) !== null) {
const before4 = t.slice(Math.max(0, m.index - 4), m.index)
const before3 = t.slice(Math.max(0, m.index - 3), m.index)
const before6 = t.slice(Math.max(0, m.index - 6), m.index)
const after = t.slice(m.index + m[1].length, m.index + m[1].length + 2)
if (neg.test(before4)) continue
if (cond.test(before3)) continue
if (quote.test(before6)) continue
if (/^[→…・]/.test(after)) continue
return true
}
return false
}
function closedRefsFromBoard() {
const closed = new Set()
try {
for (const m of readBoard()) {
if (m.from !== cfg.dispatcherName) continue
const text = String(m.text || "")
const ref = baseRef(m.ref)
if (m.kind === "result" && ref && isClosureDecl(text)) closed.add(ref)
if (m.kind === "decision") {
const re = /重开\s*([A-Za-z0-9\-]+)/g
let mm
while ((mm = re.exec(text)) !== null) closed.delete(baseRef(mm[1]))
}
}
} catch { }
return closed
}
function unreadBoard() {
const items = readBoard()
const st = loadState()
let start = 0
if (st.lastSeenBoardId) {
const idx = items.findIndex((m) => m.id === st.lastSeenBoardId)
if (idx >= 0) start = idx + 1
else start = Math.max(0, items.length - 10)
}
// Unread = entries after the cursor, not written by this agent itself,
// not bridge mirrors, and addressed to all or to this agent.
return items.slice(start).filter((m) =>
m.from!== cfg.agentName &&
!String(m.ref || '').startsWith('bridge:') &&
(m.to === 'all' || m.to === cfg.agentName || m.to === '工兵' ||!m.to))
}
// ---- 22-补：认领（claim）机制 -------------------------------------------------
// 一单被任一条线递送/接单后，另一条线不再弹卡。用文件独占创建（wx）做原子裁决，
// 避免两条线同时回合结束时各读各写 deliveredIds 造成的重复递送。
const claimsDir = join(cfg.busRoot, 'claims')
function claimFileName(ref) {
return 'order-' + String(ref).replace(/[^\w.\-]/g, '_') + '.json'
}
function claimPathOf(ref) { return join(claimsDir, claimFileName(ref)) }
function claimIsLegacy(ref) {
try { const c = JSON.parse(readFileSync(claimPathOf(ref), 'utf8')); return !('ttlMin' in c) } catch { return true }
}
function claimAgeMin(ref) {
try {
const c = JSON.parse(readFileSync(claimPathOf(ref), 'utf8'))
const t = Date.parse(String(c.at || '').replace(' ', 'T'))
if (!Number.isNaN(t)) return (Date.now() - t) / 60000
} catch { /* unreadable claim counts as expired below */ }
return Infinity
}
// v0.3 (order 47): TTL only governs v0.3+ work claims (files carrying
// ttlMin). Pre-v0.3 claim files are delivery marks and never expire; refs
// already delivered are permanent too.
function isOrderClaimed(ref) {
// 51: claims removed
return false
}
function tryClaimOrder(ref) {
// 51: claims removed, deliveredRefs dedupes
return true
}
function releaseClaim(ref) {
if (!ref) return
try { unlinkSync(claimPathOf(ref))} catch { /* ignore */}
}

// ---- 22-补：游标只推进到“实际返回的最后一条”（原实现推到 board 末尾，旧未读被吞） ----
function markRead(lastReturnedId) {
const items = readBoard()
if (!items.length) return
const st = loadState()
let target = items.length - 1
if (lastReturnedId) {
const i = items.findIndex((m) => m.id === lastReturnedId)
if (i >= 0) target = i
}
// 软唤醒按 deliveredIds + claims 走，不看游标，所以这里无需为未递送单留口子；
// 早先在此处“遇到未递送单就停”会导致游标卡死、每次读都返回同一批。
if (target < 0) return
st.lastSeenBoardId = items[target].id
saveState(st)
}

function isPendingOrder(m, delivered, closed) {
return m.from === cfg.dispatcherName &&
(m.kind === 'task' || m.kind === 'result') &&
typeof m.text === 'string' && m.text.startsWith(cfg.orderMarker) &&
!delivered.has(m.id) &&
!(closed && closed.has(baseRef(m.ref))) &&
!isOrderClaimed(m.ref)
}

// ---------- SOFT WAKE (v0.2): deliver pending orders at turn end ----------
// Activation stamp: orders posted before soft wake first went live are
// history (already handled by hand) and must never be replayed.
if (cfg.softWake) {
const st = loadState()
if (!st.softWakeSince) {
st.softWakeSince = nowTs()
saveState(st)
}
}
function pendingOrders() {
if (!cfg.softWake) return []
const st = loadState()
if (!st.softWakeSince) return []
const delivered = new Set(st.deliveredIds || [])
// 55 号：结案集（回放板上 结案/重开 帖），并落一份进状态供审计
const closed = closedRefsFromBoard()
try {
withStateLock(() => {
const s2 = loadState()
s2.closedRefs = [...closed]
saveState(s2)
})
} catch { }
return readBoard().filter((m) => String(m.ts || '') >= st.softWakeSince && isPendingOrder(m, delivered, closed))
}
async function tryDeliverOrders(fullId) {
const reserved = []
try {
if (!cfg.softWake || !fullId) return
const pendAll = pendingOrders()
if (!pendAll.length) return
let agents
try { agents = ctx.get ? ctx.get('agents') : ctx.agents } catch { agents = undefined }
if (!agents || typeof agents.get !== 'function') {
console.log('[bus-bridge] softWake: agents service unavailable in this host')
return
}
let agent
try { agent = agents.get(fullId) } catch { agent = undefined }
if (!agent || typeof agent.followup !== 'function') return

// 51-补 甲：逐单落账。锁内重读状态、剔掉已被另一线递过的单，先写 deliveredIds 再继续
// （先落账后递送）。锁内窗口毫秒级，两线不会各读旧状态再互相覆盖。
const pend = withStateLock(() => {
const st = loadState()
const done = new Set(st.deliveredIds || [])
const fresh = pendAll.filter((m) => !done.has(m.id)).slice(0, cfg.softWakeMaxOrders)
if (!fresh.length) return []
st.deliveredIds = [...(st.deliveredIds || []), ...fresh.map((m) => m.id)].slice(-300)
st.deliveredRefs = [...new Set([...(st.deliveredRefs || []), ...fresh.map((m) => String(m.ref || m.id))])].slice(-300)
st.inHand = fresh.map((m) => String(m.ref || m.id))
saveState(st)
return fresh
})
if (!pend.length) return
for (const m of pend) reserved.push(m.id)

const cum = await loadCreateUserMessage()
const createUserMessage = cum.fn
// v0.3 (order 47): slim wake signal — bodies are no longer inlined.
const prioRank = { P0: 0, P1: 1, P2: 2 }
const prioOf = (t) => {
const m = String(t || "").slice(0, 300).match(/P([012])\b/)
return m ? "P" + m[1] : "P1"
}
const orderRefs = pend.map((m) => String(m.ref || m.id))
const prios = pend.map((m) => prioOf(m.text)).sort((x, y) => (prioRank[x] ?? 1) - (prioRank[y] ?? 1))
const topPrio = prios[0] || "P1"
const text =
`【总线桥自动递送】待接 ${pend.length} 张 | 最高优先级 ${topPrio} | 单号 ${orderRefs.join("、")}\n` +
"正文不在本消息里：按单号自取——先 bus_inbox，再扫 D:\\tmp\\nailong\\bus\\board.jsonl 尾部取原文。" +
"指挥部本回合只负责开启会话，没有口述这些内容；归属以正文抬头为准。请按单执行，并回总线 ACK / 回报。"
const msg = createUserMessage
? createUserMessage({ content: [{ type: 'text', text }], source: { kind: 'user' } })
: { role: 'user', content: [{ type: 'text', text }], source: { kind: 'user' }, timestamp: Date.now() }
await agent.followup(msg)
writePresence({ status: "running", inHand: orderRefs, lastTurnStart: nowTs() })
} catch (e) {
// 递送失败：把已落账 ids 退回，下一轮还能再试
if (reserved.length) {
try {
withStateLock(() => {
const st = loadState()
st.deliveredIds = (st.deliveredIds || []).filter((id) => !reserved.includes(id))
st.deliveredRefs = (st.deliveredRefs || []).filter((r) => !reserved.includes(String(r)))
saveState(st)
})
} catch { }
}
console.log('[bus-bridge] softWake delivery failed (will retry next turn):', e?.message || e)
}
}
// v0.2.1: the message factory '@deepseek-ai/dsh-llm' resolves only from
// inside a DSH profile's module tree; this plugin physically lives outside
// it (D:\tmp\nailong), so the bare import fails (proven on the PC:
// ERR_MODULE_NOT_FOUND) and v0.2 silently fell back to a hand-rolled
// message with no `source` — the host reads source.kind when running the
// injected turn, so every delivery died with "Cannot read properties of
// undefined (reading 'kind')". Routes: (1) bare import; (2) createRequire
// anchored at the weixin plugin's real package dir, whose .pnpm sibling
// tree carries dsh-llm; (3) shape-complete fallback. The winning route is
// written to the activity log on every delivery.
let cumCache
async function loadCreateUserMessage() {
if (cumCache) return cumCache
let bareErr = 'n/a'
try {
const mod = await import('@deepseek-ai/dsh-llm')
if (typeof mod?.createUserMessage === 'function') return (cumCache = { fn: mod.createUserMessage, route: 'bare-import' })
bareErr = 'loaded but no createUserMessage export'
} catch (e) { bareErr = e?.code || e?.message || 'unknown' }
try {
const { createRequire } = await import('node:module')
const fs = await import('node:fs')
const path = await import('node:path')
const os = await import('node:os')
const { fileURLToPath } = await import('node:url')
const here = path.dirname(fileURLToPath(import.meta.url))
const anchors = [path.join(here, '..', 'dsh-plugin-weixin', 'package.json')]
for (const p of ['desktop', 'web']) {
anchors.push(path.join(os.homedir(), '.dsh', 'profiles', p, 'node_modules', 'dsh-plugin-weixin', 'package.json'))
}
for (const a of anchors) {
try {
const req = createRequire(fs.realpathSync(a))
const mod = req('@deepseek-ai/dsh-llm')
const fn = mod?.createUserMessage || mod?.default?.createUserMessage
if (typeof fn === 'function') return (cumCache = { fn, route: 'weixin-anchor' })
} catch { /* try next anchor */ }
}
} catch { /* fall through to fallback */ }
return (cumCache = { fn: undefined, route: `fallback (bare import failed: ${bareErr})` })
}
// Full session ids seen per stream key, for agents.get() at turn end.
const fullIds = new Map()
function fullIdOf(a, b) {
const e = eventOf(a, b)
const cands = [a?.id, a?.sessionId, e?.sessionId, e?.session?.id, a?.session?.id]
for (const c of cands) {
if (typeof c === 'string' && c.length >= 8) return c
}
return undefined
}

// ---------- OUTBOUND: session/event + assistant stream ----------
// Accumulate assistant text per session so turn/end can carry an excerpt.
const streams = new Map() // sessionKey -> accumulated text (capped)
function sessionKeyOf(a, b) {
const s = (a && typeof a === 'object')? (a.id?? a.sessionId): undefined
const e = (b && typeof b === 'object')? b: a
return String(s?? e?.sessionId?? e?.session?.id?? 'default')
}
function eventOf(a, b) { return (b && typeof b === 'object')? b: a}
function textFromData(data) {
if (!data) return ''
if (typeof data.text === 'string') return data.text
const content = data.message?.content?? data.content
if (typeof content === 'string') return content
if (Array.isArray(content)) {
return content.filter((c) => c && c.type === 'text' && typeof c.text === 'string')
.map((c) => c.text).join('')
}
return ''
}

try {
ctx.on('agent/assistant-stream', (payload) => {
try {
const frame = payload?.frame?? payload
if (frame?.type === 'chunk' && frame?.chunk?.type === 'text-delta') {
const key = sessionKeyOf(payload, null)
const prev = streams.get(key) || ''
if (prev.length < 20000) streams.set(key, prev + frame.chunk.text)
}
} catch { /* never break the loop */}
})
} catch (e) { console.log('[bus-bridge] assistant-stream hook unavailable:', e?.message || e)}

try {
ctx.on('session/event', (a, b) => {
try {
const event = eventOf(a, b)
const type = event?.type
if (!type) return
const key = sessionKeyOf(a, b)
const fid = fullIdOf(a, b)
if (fid) fullIds.set(key, fid)

if (type === 'assistant/message' || type === 'assistant/attempt') {
const t = textFromData(event.data)
if (t) {
const prev = streams.get(key) || ''
if (prev.length < 20000) streams.set(key, prev + t)
}
return
}

if (type === 'tool/call' || type === 'tool/result') {
// Surface "agent is blocked waiting for a human" immediately.
const raw = JSON.stringify(event.data?? '')
if (cfg.mirrorQuestions && raw.includes('ask_user_question')) {
postBoard('question',
'在 DSH 内提问，等待 Dave 回答（详情见 DSH 会话）。',
'bridge:ask_user_question')
}
return
}

if (type === 'turn/end') {
const reason = event.data?.reason?.kind?? event.data?.reason?? 'unknown'
const excerpt = oneLine(streams.get(key) || textFromData(event.data), cfg.excerptChars)
streams.delete(key)
if (cfg.mirrorTurns) {
postActivity(
`回合结束（${reason}）${excerpt? '：' + excerpt: ''}`,
`bridge:turn/${key.slice(0, 8)}`)
}
if (String(reason).includes('error')) {
try {
const dump = JSON.stringify(event.data ?? '').slice(0, 800)
if (dump && dump !== '""') postActivity(`回合错误留底：${dump}`, `bridge:turn/${key.slice(0, 8)}`)
} catch { /* ignore */ }
}
const bad = cfg.mirrorAttention && ['blocked', 'error', 'aborted', 'max-tokens'].includes(String(reason))
const stNow = loadState()
const inHand = (stNow.inHand || []).slice(0, 8)
if (bad) {
postBoard('status',
`🔴【红】回合以「${reason}」结束${inHand.length ? "，受影响单号：" + inHand.join("、") : ""}，需要关注。${excerpt ? "摘要：" + oneLine(excerpt, 300) : ""}`,
'bridge:turn-end')
}
// v0.3 (order 47): presence shared by the exception post and the app badge
writePresence({ status: bad ? 'abnormal' : 'ok', inHand: bad ? inHand : [], lastTurnEnd: nowTs(), note: bad ? oneLine(excerpt, 120) : '' })
// Soft wake: a normally-ended turn means the agent just became idle
// in a live session — hand it any dispatcher orders still waiting.
if (String(reason) === 'completed') void tryDeliverOrders(fullIds.get(key))
}
} catch { /* never break the loop */}
})
} catch (e) { console.log('[bus-bridge] session/event hook unavailable:', e?.message || e)}

// ---------- INBOUND: tools for the agent ----------
// Tool definitions are shared; only the wrapping differs. Preferred path:
// defineTool from @deepseek-ai/dsh-tools. That package is a transitive dep
// of the host bundles, so under pnpm's linked layout it may NOT be
// resolvable from this plugin's real path (observed on DSH 0.2.2-rc.1).
// Fallback: register plain tool objects directly and let the registry
// validate them. Either failure leaves mirroring fully functional.
const toolDefs = [
{
name: 'bus_inbox',
description: 'Read unread messages from the tri-party collaboration bus (board.jsonl) that were posted by Dave, Xiaozhu or others and addressed to you or everyone. Call this at the start of a task and whenever you are told new instructions may have arrived. Reading marks the messages as read.',
parameters: {
limit: { type: 'number', required: false, description: 'Max messages to return (default 20)'},
},
async execute(args) {
const all = unreadBoard()
// 22-补：取最早的一批未读（原来取最新的 limit 条，游标却跳到末尾，旧未读被永久跳过）
const items = all.slice(0, args?.limit || 20)
if (!items.length) { return 'bus inbox: no unread messages.'}
// 22-补：只推进到实际返回的最后一条；空读不推进
markRead(items[items.length - 1].id)
return items.map((m) =>
`[${m.ts}] from=${m.from} to=${m.to || 'all'} kind=${m.kind || 'note'} id=${m.id}\n${m.text}`,
).join('\n---\n')
},
},
{
name: 'bus_post',
description: 'Post a message to the tri-party collaboration bus board so Dave and Xiaozhu can see it in the shared window/phone. Use for progress reports, results and questions instead of only reporting inside DSH. Your identity (from) is set automatically.',
parameters: {
text: { type: 'string', required: true, description: 'Message text. Start with your codename paragraph marker.'},
kind: { type: 'string', required: false, description: 'note | status | task | question | decision | result (default status)'},
to: { type: 'string', required: false, description: 'Recipient: all (default)'},
},
async execute(args) {
const ok = appendJsonl(boardPath, {
ts: nowTs(), from: cfg.agentName, to: args?.to || 'all',
kind: args?.kind || 'status', text: String(args?.text || ''), ref: '', id: newId(),
})
return ok? 'bus_post: posted to board.jsonl': 'bus_post: FAILED to write board.jsonl'
},
},
]
function withOutput(def) {
return {
...def,
output: {
schema: { type: 'string'},
render: (_args, value) => [{ type: 'text', text: value}],
},
}
}
;(async () => {
let toolsSvc
try { toolsSvc = ctx.tools } catch { toolsSvc = undefined }
if (!toolsSvc?.register) {
console.log('[bus-bridge] ctx.tools registry absent in this host; tools skipped')
return
}
try {
const mod = await import('@deepseek-ai/dsh-tools')
if (typeof mod?.defineTool!== 'function') throw new Error('defineTool missing')
for (const def of toolDefs) toolsSvc.register(mod.defineTool(withOutput(def)))
console.log('[bus-bridge] tools registered via defineTool: bus_inbox, bus_post')
return
} catch (e) {
console.log('[bus-bridge] defineTool path unavailable, trying plain registration:', e?.message || e)
}
try {
for (const def of toolDefs) toolsSvc.register(withOutput(def))
console.log('[bus-bridge] tools registered via plain objects: bus_inbox, bus_post')
} catch (e) {
console.log('[bus-bridge] plain tool registration failed; tools skipped:', e?.message || e)
}
})().catch((e) => {
console.log('[bus-bridge] tools init error (mirroring unaffected):', e?.message || e)
})

console.log(`[bus-bridge] loaded; busRoot=${cfg.busRoot} agent=${cfg.agentName} softWake=${cfg.softWake}`)
}

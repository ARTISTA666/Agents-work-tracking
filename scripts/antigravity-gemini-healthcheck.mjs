#!/usr/bin/env node
// Antigravity Gemini 健康自检：一条命令区分「网络/地域」与「客户端请求构造」两类 400。
// 零依赖，需 Node 18+（用到全局 fetch / WebSocket）。只读，不修改任何文件。
// 用法：node antigravity-gemini-healthcheck.mjs
import { readFileSync } from 'node:fs';
import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import path from 'node:path';

const H = (s) => console.log('\n== ' + s + ' ==');
const p = (...parts) => path.join(homedir(), ...parts);
const sh = (bin, args) => new Promise(res => execFile(bin, args, { timeout: 15000 }, (e, so, se) => res(e ? ('ERR ' + (se || e.message)).trim() : so.trim())));
const ok = (s) => (!s || s.startsWith('ERR')) ? '' : s;

const ENDPOINT = 'https://daily-cloudcode-pa.googleapis.com';

// 1. 安装版本 + 是否有装好但没生效的暂存更新
H('1. App 版本');
console.log('installed:', await sh('defaults', ['read', p('Applications/Antigravity.app/Contents/Info.plist'), 'CFBundleShortVersionString']));
console.log('running:  ', await sh('sh', ['-c', "ps axo command | grep -m1 'Antigravity.app/Contents/MacOS/Antigravity' | cut -c1-90"]));
const staged = await sh('sh', ['-c', `f=$(ls -d ${p('Library/Caches/com.google.antigravity.ShipIt')}/update.*/Antigravity.app 2>/dev/null | head -1); [ -n "$f" ] && defaults read "$f/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null`]);
console.log('staged-but-not-installed:', ok(staged) || '(无暂存更新，说明已装最新)');

// 2. 日志错误定性（最重要的一步）
H('2. language_server.log 错误计数');
const logPath = p('Library/Logs/Antigravity/language_server.log');
let log = '';
try { log = readFileSync(logPath, 'utf8'); } catch { console.log('no log at', logPath); }
if (log) console.log('日志窗口: 首行 ' + (log.match(/[IE]\d{4} [\d:]+/)?.[0] || '?') + '，已读 ' + log.split('\n').length + ' 行（App 每次重启会轮转日志，历史计数需看归档）');
for (const [label, re] of [
  ['INVALID_ARGUMENT（客户端请求构造被拒，与 IP 无关）', /INVALID_ARGUMENT/g],
  ['User location not supported（地域白名单，换节点）', /User location is not supported/g],
  ['RESOURCE_EXHAUSTED / 429（配额）', /RESOURCE_EXHAUSTED|Too Many Requests/g],
  ['connection reset / EOF（外围长轮询抖动，多为噪声）', /connection reset by peer|unexpected EOF/g],
  ['agent executor error 总数', /agent executor error/g],
]) console.log(label, '=>', (log.match(re) || []).length);
const last = (log.match(/^.*(?:INVALID_ARGUMENT|User location).*$/gm) || []).slice(-2);
if (last.length) console.log('最近命中:\n  ' + last.map(l => l.slice(0, 180)).join('\n  '));

// 3. 端点可达性（注意：匿名请求【不能】判地域——地区校验发生在认证之后，任何出口都只返回 401）
H('3. 端点可达性与认证层（匿名 POST，恒期望 401；只验证连通，不验证地区）');
try {
  const r = await fetch(ENDPOINT + '/v1internal:generateContent', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'models/gemini-3.8-flash', contents: [{ role: 'user', parts: [{ text: 'hi' }] }] }),
    signal: AbortSignal.timeout(15000),
  });
  const j = await r.json().catch(() => ({}));
  console.log('http', r.status, '| status:', j?.error?.status, '| reason:', j?.error?.details?.[0]?.reason, '| msg:', (j?.error?.message || '').slice(0, 70));
  console.log('→ 401 CREDENTIALS_MISSING = 网络可达且已进认证层；地区结论见下一步（第 5 步）的带账号真实调用');
} catch (e) { console.log('probe failed:', e.message, '（这步才说明网络有问题）'); }

// 4. 代理链路：按进程看 chains，排除「以为走代理其实没走」
H('4. mihomo/Clash 连接里 Antigravity 的真实链路');
try {
  const cfg = readFileSync(p('Library/Application Support/com.follow.clash/config.yaml'), 'utf8');
  const ctrl = cfg.match(/^external-controller:\s*"?([^"\s]+)"?/m)?.[1];
  const secret = cfg.match(/^secret:\s*"?([^"\s]+)"?/m)?.[1];
  const r = await fetch('http://' + ctrl + '/connections', { headers: { Authorization: 'Bearer ' + secret }, signal: AbortSignal.timeout(8000) });
  const { connections = [] } = await r.json();
  const rows = connections.filter(c => {
    const m = c.metadata || {};
    return (m.process || '').includes('language_server') || /googleapis|google/.test(m.host || '');
  });
  if (!rows.length) console.log('当前没有相关连接（空闲时为空属正常）');
  for (const c of rows.slice(0, 12)) {
    const m = c.metadata || {};
    console.log(`${m.process || '-'} | ${m.host} | chains=${(c.chains || []).join(' > ') || 'DIRECT'}`);
  }
} catch (e) { console.log('控制口不可用:', e.message); }

// 5. 地域权威判定：带账号的真实调用（同 antigravity-silent-check.sh 的原理）
H('5. 带账号真实调用（地区/额度/模型可用性的权威判据，约 10~25 秒）');
const real = ok(await sh(process.env.HOME + '/.local/bin/agy', ['-p', 'Reply with exactly: PONG', '--print-timeout', '90s']));
const blob = real || '';
if (/User location is not supported/.test(blob)) console.log('❌ 出口被 Google 判为不支持地区 → 换/固定出口：scripts/default-egress-pin.sh apply');
else if (/INVALID_ARGUMENT|Request contains an invalid argument/.test(blob)) console.log('⚠️ 真实调用出现 INVALID_ARGUMENT → 与地区无关，查客户端请求构造（见对应排查记录第 5、6 节）');
else if (/PONG/.test(blob)) console.log('✅ 真实调用成功：地域、账号、模型通道均正常');
else console.log('⚠️ 未能判定（agy 不可用或输出异常）：', blob.slice(0, 240) || '(空)');

// 6. 界面残留报错卡（App 自带 CDP，只读取文本）
H('6. 界面错误卡');
try {
  const port = readFileSync(p('Library/Application Support/Antigravity/DevToolsActivePort'), 'utf8').split('\n')[0].trim();
  const ver = await (await fetch('http://127.0.0.1:' + port + '/json/version', { signal: AbortSignal.timeout(5000) })).json();
  console.log('UA:', (ver['User-Agent'] || '').match(/Antigravity\/[\d.]+/)?.[0] || '非 Antigravity 端口，跳过');
  if (!/Antigravity/.test(ver['User-Agent'] || '')) process.exit(0);
  for (const t of (await (await fetch('http://127.0.0.1:' + port + '/json')).json()).filter(t => t.type === 'page')) {
    const ws = new WebSocket(t.webSocketDebuggerUrl);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = () => rej(new Error('ws')); });
    const send = (id, method, params) => new Promise(res => {
      const h = ev => { const m = JSON.parse(ev.data); if (m.id === id) { ws.removeEventListener('message', h); res(m); } };
      ws.addEventListener('message', h); ws.send(JSON.stringify({ id, method, params }));
    });
    await send(1, 'Runtime.enable', {});
    const r = await send(2, 'Runtime.evaluate', {
      expression: `(()=>{const t=(document.body.innerText||'').split('\\n');return JSON.stringify({title:document.title,hits:t.filter(l=>/terminated due to error|INVALID_ARGUMENT|User location|Error ID/i.test(l)).slice(0,6)});})()`,
      returnByValue: true,
    });
    console.log(' ', r?.result?.result?.value ?? '(evaluate 无结果)');
    ws.close();
  }
} catch (e) { console.log('CDP 不可用（App 未运行）:', e.message); }

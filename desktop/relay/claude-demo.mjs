// Local, single-user demo bridge. Never expose this service to a network.
import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, chmodSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve, join } from 'node:path';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export function convertMessages(messages) {
  if (!Array.isArray(messages) || messages.length > 10) throw Error('Invalid messages');
  const system = messages.filter(m => m.role === 'system').map(m => m.content).join('\n');
  const content = [];
  for (const m of messages.filter(m => m.role === 'user')) {
    for (const block of typeof m.content === 'string' ? [{ type: 'text', text: m.content }] : m.content ?? []) {
      if (block.type === 'text' && typeof block.text === 'string') content.push({ type: 'text', text: block.text });
      else if (block.type === 'image_url') {
        const match = /^data:(image\/(?:jpeg|png));base64,([A-Za-z0-9+/=]+)$/.exec(block.image_url?.url ?? '');
        if (!match || match[2].length > 6_000_000) throw Error('Invalid inline image');
        content.push({ type: 'image', source: { type: 'base64', media_type: match[1], data: match[2] } });
      } else throw Error('Unsupported content');
    }
  }
  if (!content.length || typeof system !== 'string') throw Error('Missing content');
  return { system, input: { type: 'user', message: { role: 'user', content } } };
}

export function createDemoServer({ token, cli, cwd, model = 'claude-haiku-5-5', timeout = 80000 }) {
  let busy = false;
  return http.createServer(async (req, res) => {
    const reply = (status, value) => { if (!res.destroyed) { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(value)); } };
    const supplied = Buffer.from(req.headers.authorization ?? '');
    const expected = Buffer.from(`Bearer ${token}`);
    if (req.headers.origin || !/^127\.0\.0\.1:\d+$/.test(req.headers.host ?? '') || supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return reply(403, { error: { message: 'Local app authorization required.' } });
    if (req.method === 'GET' && req.url === '/v1/models') return reply(200, { data: [{ id: model, object: 'model' }] });
    if (req.method !== 'POST' || req.url !== '/v1/chat/completions') return reply(404, { error: { message: 'Unknown route.' } });
    if (busy) return reply(429, { error: { message: 'A demo request is already running.' } });
    let body = ''; let converted;
    try {
      for await (const chunk of req) { body += chunk; if (body.length > 7_000_000) throw Error('Too large'); }
      converted = convertMessages(JSON.parse(body).messages);
    } catch { return reply(400, { error: { message: 'Invalid demo request.' } }); }
    busy = true;
    const child = spawn(cli, ['-p', '--model', model, '--input-format', 'stream-json', '--output-format', 'stream-json', '--verbose', '--tools', '', '--restricted', '--strict-mcp-config', '--mcp-config', '{"mcpServers":{}}', '--setting-sources', '', '--no-session-persistence', '--disable-slash-commands', '--effort', 'low', '--system-prompt', converted.system], { cwd, env: { ...process.env, CLAUDECODE: undefined }, stdio: ['pipe', 'pipe', 'pipe'] });
    let pending = ''; let size = 0; let result; let failed = false; let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill('SIGTERM'); }, timeout);
    const killTimer = setTimeout(() => child.kill('SIGKILL'), timeout + 2000);
    res.once('close', () => { if (!res.writableEnded) child.kill('SIGTERM'); });
    // Do not log or persist screenshots, prompts, CLI output, or authentication details.
    child.stderr.on('data', () => {});
    child.stdout.on('data', chunk => {
      size += chunk.length;
      if (size > 2_000_000) { failed = true; child.kill('SIGTERM'); return; }
      pending += chunk;
      let end;
      while ((end = pending.indexOf('\n')) >= 0) {
        const line = pending.slice(0, end); pending = pending.slice(end + 1);
        try { const event = JSON.parse(line); if (event.type === 'result') result = event; } catch { failed = true; }
      }
    });
    const finish = code => {
      clearTimeout(timer); clearTimeout(killTimer); busy = false;
      if (code !== 0 || failed || timedOut || result?.is_error || typeof result?.result !== 'string' || !result.result.trim()) return reply(502, { error: { message: timedOut ? 'Claude Code timed out.' : 'Claude Code could not answer. Check its login and usage allowance in Terminal.' } });
      reply(200, { choices: [{ message: { role: 'assistant', content: result.result } }] });
    };
    child.once('error', () => { failed = true; });
    child.once('close', finish);
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify(converted.input) + '\n');
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const state = join(homedir(), 'Library/Application Support/Howdoey/ClaudeDemo');
  mkdirSync(state, { recursive: true, mode: 0o700 }); chmodSync(state, 0o700);
  const tokenPath = join(state, 'token');
  let token;
  try { token = readFileSync(tokenPath, 'utf8').trim(); } catch { token = randomBytes(32).toString('hex'); writeFileSync(tokenPath, token, { mode: 0o600 }); }
  chmodSync(tokenPath, 0o600);
  const server = createDemoServer({ token, cli: process.env.HOWDOEY_CLAUDE_BIN ?? join(homedir(), '.local/bin/claude'), cwd: state });
  server.listen(8767, '127.0.0.1', () => console.log('Howdoey Claude Code demo listening on 127.0.0.1:8767. Screen context goes to your signed-in Claude account.'));
}

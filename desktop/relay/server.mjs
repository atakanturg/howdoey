// Howdoey Groq relay. Node 24+, built-in modules only. No developer secret in the app.
import http from 'node:http';
import { DatabaseSync } from 'node:sqlite';
import { randomBytes, createHash, timingSafeEqual } from 'node:crypto';
import { mkdirSync, chmodSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const hash = value => createHash('sha256').update(value).digest('hex');
const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
class HTTPError extends Error { constructor(status, message) { super(message); this.status = status; } }
export class TokenStore {
  constructor(path = ':memory:', limits = {}) {
    if (path !== ':memory:') { mkdirSync(dirname(path), {recursive:true, mode:0o700}); }
    this.db = new DatabaseSync(path);
    if (path !== ':memory:') chmodSync(path, 0o600);
    this.limits = {minute:6, day:30, globalDay:100, ...limits};
    this.db.exec(`PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS clients (hash TEXT PRIMARY KEY, label TEXT NOT NULL, expires INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS usage (scope TEXT, period TEXT, count INTEGER NOT NULL, PRIMARY KEY(scope,period));`);
  }
  issue(label, days = 7) {
    if (!label || label.length > 80 || !Number.isInteger(days) || days < 1 || days > 90) throw new HTTPError(400,'Use a label and an expiry of 1–90 days.');
    const token = 'hd_' + randomBytes(32).toString('base64url');
    const id = hash(token);
    this.db.prepare('INSERT INTO clients(hash,label,expires) VALUES(?,?,?)').run(id,label,Date.now()+days*86400000);
    return {token, id};
  }
  list() { return this.db.prepare('SELECT hash AS id,label,expires,revoked FROM clients ORDER BY expires DESC').all(); }
  revoke(id) { this.db.prepare('UPDATE clients SET revoked=1 WHERE hash=?').run(id); }
  authenticate(token) {
    if (typeof token !== 'string' || !/^hd_[A-Za-z0-9_-]{43}$/.test(token)) throw new HTTPError(401,'A valid Howdoey access token is required.');
    const id = hash(token);
    const row = this.db.prepare('SELECT expires,revoked FROM clients WHERE hash=?').get(id);
    if (!row || row.revoked || row.expires < Date.now()) throw new HTTPError(401,'This access token is invalid, expired, or revoked.');
    return id;
  }
  reserve(id, now = Date.now()) {
    const day = new Date(now).toISOString().slice(0,10);
    const minute = String(Math.floor(now/60000));
    const counters = [[id, 'minute:'+minute, this.limits.minute], [id,'day:'+day,this.limits.day], ['global','day:'+day,this.limits.globalDay]];
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const [scope,period,limit] of counters) {
        const row = this.db.prepare('SELECT count FROM usage WHERE scope=? AND period=?').get(scope,period);
        if ((row?.count ?? 0) >= limit) throw new HTTPError(429,'Usage limit reached. Try later or contact the developer.');
      }
      for (const [scope,period] of counters) this.db.prepare('INSERT INTO usage(scope,period,count) VALUES(?,?,1) ON CONFLICT(scope,period) DO UPDATE SET count=count+1').run(scope,period);
      // Keep the metadata small without storing any prompt or response content.
      this.db.prepare('DELETE FROM usage WHERE period LIKE ? AND period < ?').run('minute:%','minute:'+String(Math.floor(now/60000)-1440));
      this.db.exec('COMMIT');
    } catch (error) { this.db.exec('ROLLBACK'); throw error; }
  }
}
export function validateCompletion(body, configuredModel) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HTTPError(400,'Expected a JSON object.');
  if (Object.keys(body).some(k=>!['model','messages','temperature','max_tokens','stream'].includes(k))) throw new HTTPError(400,'Unsupported request fields.');
  if (body.model !== configuredModel) throw new HTTPError(400,'Choose the model offered by this Howdoey service.');
  if (body.stream === true) throw new HTTPError(400,'Streaming is not supported by this relay.');
  if (!Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 20) throw new HTTPError(400,'Invalid messages.');
  let textBytes = 0, images = 0;
  const messages = body.messages.map(message => {
    if (!message || !['system','user','assistant'].includes(message.role)) throw new HTTPError(400,'Invalid message role.');
    let content;
    const text = value => { if (typeof value !== 'string') throw new HTTPError(400,'Invalid text.'); textBytes += Buffer.byteLength(value); return value; };
    if (typeof message.content === 'string') content = text(message.content);
    else if (Array.isArray(message.content) && message.content.length <= 4) {
      content = message.content.map(part => {
        if (part?.type === 'text') return {type:'text',text:text(part.text)};
        if (part?.type === 'image_url' && message.role === 'user' && typeof part.image_url?.url === 'string') {
          images++;
          const url = part.image_url.url;
          if (!/^data:image\/(jpeg|png);base64,[A-Za-z0-9+/]+={0,2}$/.test(url) || url.length > 1800000) throw new HTTPError(400,'Only bounded inline JPEG or PNG images are accepted.');
          return {type:'image_url',image_url:{url}};
        }
        throw new HTTPError(400,'Unsupported message content.');
      });
    } else throw new HTTPError(400,'Invalid content.');
    return {role:message.role,content};
  });
  if (textBytes > 140000 || images > 1) throw new HTTPError(413,'Too much screen context. Select a smaller area.');
  if (body.max_tokens !== undefined && (!Number.isInteger(body.max_tokens) || body.max_tokens < 1 || body.max_tokens > 1800)) throw new HTTPError(400,'Output limit must be 1–1800 tokens.');
  return {model:configuredModel,messages,max_tokens:body.max_tokens ?? 1800,temperature:0.2,stream:false};
}
async function readBody(req, limit = 2100000) {
  if (req.headers['transfer-encoding'] || !/^\d+$/.test(req.headers['content-length'] ?? '')) throw new HTTPError(411,'A Content-Length is required.');
  if (Number(req.headers['content-length']) > limit) throw new HTTPError(413,'Request too large.');
  let size=0; const chunks=[];
  for await (const chunk of req) { size+=chunk.length; if(size>limit) throw new HTTPError(413,'Request too large.'); chunks.push(chunk); }
  return Buffer.concat(chunks).toString('utf8');
}
export function createRelay({store, publicOrigin = null, transport = null, key = '', model = ''}) {
  let groqKey=key, selectedModel=model, active=0;
  let keyValidated=!!key && !!model, modelIDs=model ? [model] : [];
  const csrf=randomBytes(32).toString('hex');
  const upstream = transport ?? (async (route, payload) => {
    const response = await fetch('https://api.groq.com/openai/v1/'+route, {
      method: payload ? 'POST':'GET', redirect:'error', signal:AbortSignal.timeout(60000),
      headers:{Authorization:'Bearer '+groqKey,'Content-Type':'application/json'}, body:payload ? JSON.stringify(payload):undefined
    });
    if (!response.ok) {
      if (response.status === 401) { keyValidated=false; selectedModel=''; }
      throw new HTTPError(response.status===429?429:502, response.status===401 ? 'Groq rejected the key (401). Paste the actual secret key from Groq, not the name you gave it. Your key must stay out of chat.' : 'Groq request failed (HTTP '+response.status+'). Check the developer key and model.');
    }
    // Never return raw provider errors; they may echo captured content.
    const data = await response.json();
    return data;
  });
  const send = (res,status,data,type='application/json') => {
    const body = type==='application/json'?JSON.stringify(data):data;
    res.writeHead(status, {'Content-Type':type+'; charset=utf-8','Content-Length':Buffer.byteLength(body),'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'same-origin','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'"}); res.end(body);
  };
  const page = (content) => `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Howdoey developer setup</title><style>body{font:17px system-ui;max-width:680px;margin:50px auto;padding:24px;background:#f3f6fb;color:#182b45}input,select,button{font:inherit;padding:10px;margin:8px 0;width:100%;box-sizing:border-box}button{background:#2158a0;color:white;border:0;border-radius:10px}code{overflow-wrap:anywhere}section{background:white;padding:22px;border-radius:16px;margin:20px 0}label{display:block;margin-top:12px}</style><h1>Howdoey developer setup</h1><p>Local developer page. Your Groq key stays in this server's memory and goes only to Groq. It is never sent to the macOS app or testers. Restarting this local server clears the key.</p>${content}</html>`;
  const hidden = () => `<input type="hidden" name="csrf" value="${csrf}">`;
  const adminHome = (notice='') => page(`${notice ? `<section role="alert"><p>${escape(notice)}</p></section>` : ''}
    <section><h2>1. Developer Groq key</h2><p>${keyValidated?'Key validated with Groq.':'A valid key is required. Use the secret value, not its label (such as Howdoey).'}</p>
    <form method="post" action="/admin/configure">${hidden()}<label>Groq secret key<input name="key" type="password" autocomplete="off" required></label><button>Validate key and choose a model automatically</button></form></section>
    <section><h2>2. Model</h2><p>${selectedModel ? 'Current model: '+escape(selectedModel) : 'Models appear after your key is validated. You do not need to find a model ID.'}</p>
    ${keyValidated && modelIDs.length ? `<form method="post" action="/admin/model">${hidden()}<label>Available model<select name="model">${modelIDs.map(id=>`<option value="${escape(id)}" ${id===selectedModel?'selected':''}>${escape(id)}</option>`).join('')}</select></label><button>Change model</button></form>` : ''}</section>
    <section><h2>3. Create a tester’s access</h2><p>Each tester gets an expiring, revocable token. This is not your Groq key. Limits: ${store.limits.minute}/minute, ${store.limits.day}/day per tester; ${store.limits.globalDay}/day total.</p>
    ${keyValidated && selectedModel ? `<form method="post" action="/admin/token">${hidden()}<label>Tester label<input name="label" required maxlength="80"></label><label>Expires in days<input name="days" type="number" value="7" min="1" max="90" required></label><button>Create access token</button></form>` : '<p>Validate the key above first to enable access tokens.</p>'}</section>
    <section><h2>Access management</h2>${store.list().map(c=>`<p>${escape(c.label)} · ${c.revoked?'revoked':'expires '+escape(new Date(c.expires).toISOString().slice(0,10))}</p>${c.revoked?'':`<form method="post" action="/admin/revoke">${hidden()}<input name="id" type="hidden" value="${c.id}"><button>Revoke ${escape(c.label)}</button></form>`}`).join('')||'<p>No tokens yet.</p>'}</section>`);
  const server=http.createServer(async (req,res)=>{
    const expected = publicOrigin ? new URL(publicOrigin).host : '127.0.0.1:'+server.address().port;
    if (req.headers.host!==expected) return send(res,400,{error:{message:'Unexpected Host.'}});
    if (++active>24) { active--; return send(res,503,{error:{message:'Service busy.'}}); }
    try {
      if (req.url==='/health' && req.method==='GET') return send(res,200,{ready:keyValidated&&!!selectedModel});
      if (req.url.startsWith('/admin')) {
        if (publicOrigin || !['127.0.0.1','::1','::ffff:127.0.0.1'].includes(req.socket.remoteAddress)) throw new HTTPError(404,'Not found.');
        if (req.method==='GET' && ['/admin','/admin/configure','/admin/token','/admin/model'].includes(req.url)) return send(res,200,adminHome(),'text/html');
        // Some embedded browsers submit same-page forms with a missing/opaque Origin.
        // An explicit foreign origin is denied; every POST still needs the unguessable
        // token from this server's form, protected by SOP, CSP and strict Host checking.
        const origin=req.headers.origin;
        if (req.method!=='POST' || (origin && origin!=='null' && origin!=='http://'+expected) || !req.headers['content-type']?.startsWith('application/x-www-form-urlencoded')) throw new HTTPError(403,'Invalid local setup request. Use the form at http://'+expected+'/admin.');
        const form=new URLSearchParams(await readBody(req,10000));
        const token=form.get('csrf')??'';
        if (Buffer.byteLength(token)!==Buffer.byteLength(csrf)||!timingSafeEqual(Buffer.from(token),Buffer.from(csrf))) throw new HTTPError(403,'Invalid setup token.');
        if (req.url==='/admin/configure') {
          const next=form.get('key')?.trim();
          if(!next||next.length>512||/[\r\n]/.test(next)) throw new HTTPError(400,'Enter a valid Groq key.');
          groqKey=next; keyValidated=false; selectedModel=''; modelIDs=[];
          const result=await upstream('models');
          modelIDs=[...new Set((result.data??[]).map(m=>m.id).filter(id=>typeof id==='string' && id.length<=200))].sort();
          if (!modelIDs.length) throw new HTTPError(502,'Groq returned no available models. Check your account access.');
          keyValidated=true;
          selectedModel=['qwen/qwen3.8-27b','openai/gpt-oss-20b','llama-3.3-70b-versatile','llama-3.1-8b-instant'].find(id=>modelIDs.includes(id)) ?? modelIDs.find(id=>!/whisper|tts|guard|safeguard/i.test(id)) ?? '';
          return send(res,200,adminHome('Key validated. A model has been selected; you can now create your access token. Screenshots require a model that supports vision.'),'text/html');
        }
        if(req.url==='/admin/model') {
          const next=form.get('model')?.trim(); if(!keyValidated||!modelIDs.includes(next)) throw new HTTPError(400,'Choose an available model after validating your key.');
          selectedModel=next; return send(res,200,adminHome(),'text/html');
        }
        if(req.url==='/admin/token') {
          if(!keyValidated||!selectedModel) throw new HTTPError(409,'Configure the key and model first.');
          const issued=store.issue(form.get('label'),Number(form.get('days')));
          return send(res,200,page(`<section><h2>Access created</h2><p>Copy this token now. The service stores only its SHA-256 hash. Do not put the token in chat or source code.</p><code>${issued.token}</code><p>In Howdoey settings choose Howdoey shared AI.</p><p>Address: <code>http://${expected}/v1</code><br>Model: <code>${escape(selectedModel)}</code><br>API key field: paste the access token above, then Save.</p><p>This loopback address works only on this Mac. Other computers need a deployed HTTPS relay and their own token.</p><a href="/admin">Back to setup</a></section>`),'text/html');
        }
        if(req.url==='/admin/revoke') { store.revoke(form.get('id')??''); return send(res,200,adminHome(),'text/html'); }
        throw new HTTPError(404,'Not found.');
      }
      const token=req.headers.authorization?.replace(/^Bearer /,'');
      const client=store.authenticate(token);
      if(!keyValidated||!selectedModel) throw new HTTPError(503,'The developer must configure the service first.');
      if(req.url==='/v1/models'&&req.method==='GET') return send(res,200,{object:'list',data:[{id:selectedModel,object:'model',owned_by:'howdoey'}]});
      if(req.url==='/v1/chat/completions'&&req.method==='POST') {
        if(!req.headers['content-type']?.startsWith('application/json')) throw new HTTPError(415,'Expected JSON.');
        let body; try{body=JSON.parse(await readBody(req));}catch(error){if(error instanceof HTTPError)throw error;throw new HTTPError(400,'Invalid JSON.');}
        const payload=validateCompletion(body,selectedModel);
        store.reserve(client);
        const result=await upstream('chat/completions',payload);
        const text=result?.choices?.[0]?.message?.content;
        if(typeof text!=='string'||text.length>30000) throw new HTTPError(502,'The model returned no usable answer.');
        // Return only what the app needs. Never forward provider headers or arbitrary response fields.
        return send(res,200,{choices:[{message:{role:'assistant',content:text}}]});
      }
      throw new HTTPError(404,'Not found.');
    } catch(error) {
      if(!res.headersSent) {
        const status=error instanceof HTTPError?error.status:502;
        const message=error instanceof HTTPError?error.message:'The AI service could not complete the request.';
        if (!publicOrigin && req.url.startsWith('/admin')) send(res,status,adminHome(message),'text/html');
        else send(res,status,{error:{message}});
      }
    }
    finally { active--; }
  });
  server.requestTimeout=75000; server.headersTimeout=10000; server.timeout=80000; server.maxRequestsPerSocket=100;
  return server;
}
if (process.argv[1] && import.meta.url===pathToFileURL(resolve(process.argv[1])).href) {
  process.umask(0o077);
  const dbPath=resolve(process.env.HOWDOEY_RELAY_DB??new URL('./.state/relay.sqlite',import.meta.url).pathname);
  const limit = (name,fallback) => {const n=Number(process.env[name]??fallback);if(!Number.isSafeInteger(n)||n<1)throw new Error('Invalid '+name);return n;};
  const store=new TokenStore(dbPath,{minute:limit('HOWDOEY_PER_MINUTE',6),day:limit('HOWDOEY_PER_USER_DAY',30),globalDay:limit('HOWDOEY_GLOBAL_DAY',100)});
  if(process.argv[2]==='issue-token') {
    const issued=store.issue(process.argv[3],Number(process.argv[4]??7)); console.log(issued.token); process.exit(0);
  }
  const publicOrigin=process.env.HOWDOEY_PUBLIC_ORIGIN??null;
  if(publicOrigin && (new URL(publicOrigin).protocol!=='https:'||new URL(publicOrigin).origin!==publicOrigin)) throw new Error('Public origin must be an HTTPS origin without a path.');
  if(publicOrigin&&(!process.env.GROQ_API_KEY||!process.env.HOWDOEY_MODEL)) throw new Error('Set GROQ_API_KEY and HOWDOEY_MODEL in the hosting secret manager.');
  const server=createRelay({store,publicOrigin,key:process.env.GROQ_API_KEY??'',model:process.env.HOWDOEY_MODEL??''});
  const port=Number(process.env.PORT??8766);
  server.listen(port,'127.0.0.1',()=>console.log(publicOrigin?'Howdoey relay listening behind HTTPS proxy; local admin disabled.':`Howdoey local developer setup: http://127.0.0.1:${port}/admin`));
}

import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
const rawStatus = (base,host,path) => new Promise((resolve,reject)=>{http.get(base+path,{headers:{Host:host}},res=>{res.resume();resolve(res.statusCode);}).on('error',reject);});
import { TokenStore, createRelay, validateCompletion } from './server.mjs';

const payload = {model:'test-model',messages:[{role:'system',content:'A real protocol test fixture.'},{role:'user',content:'hello'}],max_tokens:1800,stream:false};
async function running(options={}) {
  const store=options.store??new TokenStore();
  const server=createRelay({store,key:'test-only-not-a-real-key',model:'test-model',...options});
  server.listen(0,'127.0.0.1'); await once(server,'listening');
  return {store,server,base:'http://127.0.0.1:'+server.address().port,close:()=>new Promise(resolve=>server.close(resolve))};
}
test('per-user tokens can be expired and revoked; database never stores plaintext tokens',()=>{
  const store=new TokenStore(); const issued=store.issue('tester');
  assert.equal(store.authenticate(issued.token),issued.id);
  assert.ok(!JSON.stringify(store.list()).includes(issued.token));
  store.revoke(issued.id); assert.throws(()=>store.authenticate(issued.token),/revoked/);
  const expired=store.issue('expired'); store.db.prepare('UPDATE clients SET expires=0 WHERE hash=?').run(expired.id);
  assert.throws(()=>store.authenticate(expired.token),/expired/);
});
test('per-user and global budgets are enforced before upstream use',()=>{
  const store=new TokenStore(':memory:',{minute:1,day:2,globalDay:2});
  const a=store.issue('a'),b=store.issue('b'),c=store.issue('c');
  store.reserve(a.id); assert.throws(()=>store.reserve(a.id),/limit/);
  store.reserve(b.id); assert.throws(()=>store.reserve(c.id),/limit/);
});
test('rejects model switching, tools, remote images, large output and extra images',()=>{
  assert.equal(validateCompletion(payload,'test-model').max_tokens,1800);
  assert.throws(()=>validateCompletion({...payload,model:'expensive-other-model'},'test-model'));
  assert.throws(()=>validateCompletion({...payload,tools:[]},'test-model'));
  assert.throws(()=>validateCompletion({...payload,max_tokens:99999},'test-model'));
  const image={type:'image_url',image_url:{url:'https://attacker.invalid/image.jpg'}};
  assert.throws(()=>validateCompletion({...payload,messages:[{role:'user',content:[image]}]},'test-model'));
  const inline={type:'image_url',image_url:{url:'data:image/jpeg;base64,YWJj'}};
  assert.throws(()=>validateCompletion({...payload,messages:[{role:'user',content:[inline,inline]}]},'test-model'));
});
test('relay requires auth and never forwards provider secrets or extra response fields',async()=>{
  let calls=0;
  const app=await running({transport:async(route,body)=>{calls++;assert.equal(route,'chat/completions');assert.equal(body.model,'test-model');return {choices:[{message:{content:'test fixture reply'}}],private_field:'DO NOT FORWARD'};}});
  try{
    assert.equal((await fetch(app.base+'/v1/models')).status,401);
    const token=app.store.issue('integration').token;
    const headers={Authorization:'Bearer '+token,'Content-Type':'application/json'};
    const models=await (await fetch(app.base+'/v1/models',{headers})).json();assert.equal(models.data[0].id,'test-model');
    const response=await fetch(app.base+'/v1/chat/completions',{method:'POST',headers,body:JSON.stringify(payload)});
    assert.equal(response.status,200);const text=await response.text();
    assert.ok(text.includes('test fixture reply'));assert.ok(!text.includes('DO NOT FORWARD'));assert.ok(!text.includes('test-only-not-a-real-key'));assert.equal(calls,1);
  }finally{await app.close();}
});
test('Host and CSRF validation protect the local developer form',async()=>{
  const app=await running();
  try{
    assert.equal(await rawStatus(app.base,'evil.invalid','/admin'),400);
    const html=await (await fetch(app.base+'/admin')).text();assert.ok(!html.includes('test-only-not-a-real-key'));
    const csrf=html.match(/name="csrf" value="([a-f0-9]+)"/)[1];
    const post=(origin,value)=>fetch(app.base+'/admin/model',{method:'POST',headers:{Origin:origin,'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({csrf:value,model:'test-model'})});
    assert.equal((await post('https://evil.invalid',csrf)).status,403);
    assert.equal((await post(app.base,'wrong')).status,403);
    assert.equal((await post(app.base,csrf)).status,200);
    assert.equal((await post('null',csrf)).status,200);
    assert.equal((await post('null','wrong')).status,403);
    assert.equal((await post('https://evil.invalid','wrong')).status,403);
  }finally{await app.close();}
});
test('public-mode server never exposes developer setup',async()=>{
  const app=await running({publicOrigin:'https://relay.example.com'});
  try { assert.equal(await rawStatus(app.base,'relay.example.com','/admin'),404); }
  finally{await app.close();}
});
test('failed upstream errors are sanitized and still count against budget',async()=>{
  const store=new TokenStore(':memory:',{minute:1});
  const app=await running({store,transport:async()=>{throw new Error('secret provider error body');}});
  try{
    const headers={Authorization:'Bearer '+store.issue('errors').token,'Content-Type':'application/json'};
    const post=()=>fetch(app.base+'/v1/chat/completions',{method:'POST',headers,body:JSON.stringify(payload)});
    const first=await post();assert.equal(first.status,502);assert.ok(!(await first.text()).includes('secret provider'));
    assert.equal((await post()).status,429);
  }finally{await app.close();}
});

test('setup validates before readiness, automatically chooses a model, and renders recoverable errors',async()=>{
  let rejectKey=true;
  const app=await running({key:'',model:'',transport:async()=>{
    if(rejectKey) throw new Error('private provider rejection');
    return {data:[{id:'whisper-large-v3'},{id:'openai/gpt-oss-20b'}]};
  }});
  try {
    let html=await (await fetch(app.base+'/admin/token')).text();
    assert.ok(html.includes('Validate the key above first')); assert.ok(!html.includes('name="model"'));
    const csrf=html.match(/name="csrf" value="([a-f0-9]+)"/)[1];
    const post=(path,fields)=>fetch(app.base+path,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({csrf,...fields})});
    let response=await post('/admin/token',{label:'early',days:'1'});
    assert.equal(response.status,409); assert.ok(response.headers.get('content-type').includes('text/html'));
    response=await post('/admin/configure',{key:'fixture-only'}); assert.equal(response.status,502);
    assert.equal((await (await fetch(app.base+'/health')).json()).ready,false);
    rejectKey=false;
    response=await post('/admin/configure',{key:'fixture-only'}); html=await response.text();
    assert.equal(response.status,200); assert.ok(html.includes('<select name="model">')); assert.ok(html.includes('value="openai/gpt-oss-20b" selected'));
    assert.equal((await (await fetch(app.base+'/health')).json()).ready,true);
    assert.equal((await post('/admin/model',{model:'invented-model'})).status,400);
    assert.equal((await post('/admin/token',{label:'tester',days:'1'})).status,200);
  } finally { await app.close(); }
});

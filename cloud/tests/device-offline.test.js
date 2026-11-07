import {env} from 'cloudflare:workers';
import {runInDurableObject,runDurableObjectAlarm} from 'cloudflare:test';
import {afterAll,beforeAll,beforeEach,expect,it,vi} from 'vitest';
import migration from '../migrations/0001_registry.sql?raw';
import connectionsMigration from '../migrations/0002_connections.sql?raw';
import usersMigration from '../migrations/0003_users.sql?raw';
import worker from '../src/index.js';
import {OFFLINE_NOTICE_MS} from '../src/device.js';
import {envelope,token} from '../src/common.js';
// The fake verifier carries an email only when a test asks for one, like a Firebase token with or without the claim.
vi.mock('../src/auth.js',async()=>{const {Failure}=await import('../src/common.js');return {authenticate:async r=>{const user=r.headers.get('Authorization')?.slice(7);if(!['alice','bob'].includes(user))throw new Failure('unauthorized',401);const p={user_id:user,client_id:'test-client'};const email=r.headers.get('X-Test-Email');if(email)Object.assign(p,{email,email_verified:true});return p}}});
let ip,sent,originalEmail;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
beforeAll(async()=>{originalEmail=env.EMAIL;for(const sql of (migration+connectionsMigration+usersMigration).split(';').filter(s=>s.trim()))await env.DB.prepare(sql).run()});
beforeEach(async()=>{ip=crypto.randomUUID();sent=[];for(const table of ['connections','consent_requests','tokens','pairing','devices','deleting','users'])await env.DB.prepare('DELETE FROM '+table).run()});
afterAll(()=>{env.EMAIL=originalEmail});
function request(path,method='GET',data,who='alice',email){return worker.fetch(new Request('https://api.example'+path,{method,headers:{Authorization:'Bearer '+who,'CF-Connecting-IP':ip,'Content-Type':'application/json',...(email?{'X-Test-Email':email}:{})},body:data?JSON.stringify(data):undefined}),env)}
async function pair(){const r=await request('/v1/pairing/code','POST',{kind:'mac',device_name:'Test Mac',agent_version:'0.8.0'});expect(r.status).toBe(200);const p=await r.json(),raw=token();expect((await request('/v1/pairing/claim','POST',{code:p.code})).status).toBe(200);expect((await request('/v1/pairing/redeem','POST',{device_token:raw},p.bootstrap_token)).status).toBe(200);return {...p,raw,stub:env.DEVICES.getByName(p.device_id)}}
function inbox(ws){const queue=[],waiters=[];ws.addEventListener('message',e=>{const v=JSON.parse(e.data),waiter=waiters.shift();if(waiter)waiter(v);else queue.push(v)});return ()=>queue.length?Promise.resolve(queue.shift()):new Promise(r=>waiters.push(r))}
async function connect(p){const r=await worker.fetch(new Request('https://api.example/v1/ws/device',{headers:{Upgrade:'websocket','X-Wand-Device-ID':p.device_id,'CF-Connecting-IP':ip}}),env);expect(r.status).toBe(101);const ws=r.webSocket;ws.accept();const next=inbox(ws);ws.send(JSON.stringify(envelope('hello',{device_token:p.raw,agent_version:'0.8.0',device_name:'Test Mac',macos_version:'26'})));expect((await next()).type).toBe('ready');return {ws,next}}
const state=stub=>runInDurableObject(stub,async o=>({since:o.get('offline_since'),notifyAt:o.get('offline_notify_at'),notified:o.get('offline_notified'),attempts:o.get('offline_attempts'),alarm:await o.ctx.storage.getAlarm()}));
async function waitOffline(stub){for(let n=0;n<100;n++){const s=await state(stub);if(s.since)return s;await sleep(10)}throw Error('The device never went offline')}
// Move the whole episode into the past so the six hour deadline arrives without waiting, then run the alarm the
// way the runtime would. A real past-due alarm would fire on its own within milliseconds, racing the assertions.
const elapse=(stub,ms)=>runInDurableObject(stub,o=>{o.put('offline_since',Number(o.get('offline_since'))-ms);o.put('offline_notify_at',Number(o.get('offline_notify_at'))-ms);o.put('last_seen',new Date(Date.parse(o.get('last_seen'))-ms).toISOString())});
const fire=stub=>runInDurableObject(stub,o=>o.alarm());
const mailbox=(stub,binding={send:async m=>{sent.push(m);return {messageId:'m'+sent.length}}})=>runInDurableObject(stub,o=>{o.env.EMAIL=binding});
async function goOffline(p,ws){ws.close();return waitOffline(p.stub)}

it('remembers a verified owner email from the token and rewrites it only when it changes',async()=>{
 expect((await request('/v1/devices','GET',undefined,'alice','alice@example.com')).status).toBe(200);
 const first=await env.DB.prepare('SELECT * FROM users WHERE user_id=?').bind('alice').first();
 expect(first).toMatchObject({email:'alice@example.com',email_verified:1});
 await sleep(5);await request('/v1/devices','GET',undefined,'alice','alice@example.com');
 expect((await env.DB.prepare('SELECT updated_at FROM users WHERE user_id=?').bind('alice').first()).updated_at).toBe(first.updated_at);
 await request('/v1/devices','GET',undefined,'alice','renamed@example.com');
 const changed=await env.DB.prepare('SELECT * FROM users WHERE user_id=?').bind('alice').first();
 expect(changed.email).toBe('renamed@example.com');expect(changed.updated_at).not.toBe(first.updated_at);
 // A token without an email claim leaves the stored address alone, and never invents a row.
 await request('/v1/devices');await request('/v1/devices','GET',undefined,'bob');
 expect((await env.DB.prepare('SELECT email FROM users WHERE user_id=?').bind('alice').first()).email).toBe('renamed@example.com');
 expect(await env.DB.prepare('SELECT * FROM users WHERE user_id=?').bind('bob').first()).toBeNull();
 expect((await request('/v1/account','DELETE')).status).toBe(200);
 expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM users').first()).n).toBe(0);
});
it('starts an offline episode when the socket goes away and schedules the notice six hours out',async()=>{
 const p=await pair(),{ws}=await connect(p);
 expect((await state(p.stub)).since).toBeUndefined();
 const before=Date.now(),s=await goOffline(p,ws);
 expect(Number(s.since)).toBeGreaterThanOrEqual(before-1000);expect(Number(s.since)).toBeLessThanOrEqual(Date.now());
 expect(Number(s.notifyAt)).toBe(Number(s.since)+OFFLINE_NOTICE_MS);
 expect(s.alarm).toBe(Number(s.notifyAt));expect(s.notified).toBeUndefined();
 expect((await p.stub.presence()).online).toBe(false);
});
it('sends one email after six hours, none before, and only once per episode until a reconnect',async()=>{
 await request('/v1/devices','GET',undefined,'alice','alice@example.com');
 const p=await pair();let {ws}=await connect(p);await goOffline(p,ws);await mailbox(p.stub);
 await elapse(p.stub,3600000);await fire(p.stub);
 expect(sent).toHaveLength(0);const early=await state(p.stub);expect(early.notified).toBeUndefined();expect(early.alarm).toBe(Number(early.notifyAt));
 await elapse(p.stub,5*3600000+1000);await fire(p.stub);
 expect(sent).toHaveLength(1);
 expect(sent[0].to).toBe('alice@example.com');expect(sent[0].from).toEqual({email:'wand@getwand.app',name:'Wand'});
 expect(sent[0].subject).toMatch(/^Wand on Test Mac has been offline since \d{1,2} [A-Z][a-z]+ \d{4} at \d\d:\d\d UTC$/);
 expect(sent[0].text).toContain('about 6 hours ago');expect(sent[0].text).toContain('alice@example.com owns this Mac');
 expect((await state(p.stub)).notified).toBe('1');
 await fire(p.stub);await runDurableObjectAlarm(p.stub);expect(sent).toHaveLength(1);
 // Coming back clears the episode; the next outage is a new one.
 ({ws}=await connect(p));const back=await state(p.stub);expect(back.since).toBeUndefined();expect(back.notified).toBeUndefined();
 await goOffline(p,ws);expect(sent).toHaveLength(1);
 await elapse(p.stub,OFFLINE_NOTICE_MS+1000);await fire(p.stub);expect(sent).toHaveLength(2);
});
it('never emails about a revoked device',async()=>{
 await request('/v1/devices','GET',undefined,'alice','alice@example.com');
 const p=await pair(),{ws}=await connect(p);await goOffline(p,ws);await mailbox(p.stub);await elapse(p.stub,OFFLINE_NOTICE_MS+1000);
 expect((await request('/v1/devices/'+p.device_id,'DELETE')).status).toBe(200);
 expect((await state(p.stub)).since).toBeUndefined();
 // Even stale episode state left behind cannot produce mail once the object is revoked.
 await runInDurableObject(p.stub,async o=>{o.put('offline_since',Date.now()-OFFLINE_NOTICE_MS-1000);o.put('offline_notify_at',Date.now()-1000);await o.alarm()});
 expect(sent).toHaveLength(0);
 // A device revoked in the registry while the object still thinks it is paired sends nothing either.
 const q=await pair(),second=await connect(q);await goOffline(q,second.ws);await mailbox(q.stub);await elapse(q.stub,OFFLINE_NOTICE_MS+1000);
 await env.DB.prepare('UPDATE devices SET revoked_at=? WHERE id=?').bind(new Date().toISOString(),q.device_id).run();
 await fire(q.stub);expect(sent).toHaveLength(0);expect((await state(q.stub)).notified).toBe('1');
});
it('sends nothing and does not throw without a users row, with a deleting owner, or without the EMAIL binding',async()=>{
 const p=await pair(),a=await connect(p);await goOffline(p,a.ws);await mailbox(p.stub);await elapse(p.stub,OFFLINE_NOTICE_MS+1000);
 await fire(p.stub);expect(sent).toHaveLength(0);
 const quiet=await state(p.stub);expect(quiet.notified).toBe('1');expect(quiet.alarm===null||quiet.alarm>Date.now()+OFFLINE_NOTICE_MS).toBe(true);
 await request('/v1/devices','GET',undefined,'alice','alice@example.com');
 const q=await pair(),b=await connect(q);await goOffline(q,b.ws);await mailbox(q.stub);await elapse(q.stub,OFFLINE_NOTICE_MS+1000);
 await env.DB.prepare('INSERT INTO deleting VALUES(?)').bind('alice').run();
 await fire(q.stub);expect(sent).toHaveLength(0);
 await env.DB.prepare('DELETE FROM deleting').run();
 const r=await pair(),c=await connect(r);await goOffline(r,c.ws);await mailbox(r.stub,null);await elapse(r.stub,OFFLINE_NOTICE_MS+1000);
 await fire(r.stub);expect(sent).toHaveLength(0);expect((await state(r.stub)).notified).toBe('1');
});
it('retries a provider failure a few times and then gives up for the episode',async()=>{
 await request('/v1/devices','GET',undefined,'alice','alice@example.com');
 const p=await pair(),{ws}=await connect(p);await goOffline(p,ws);await elapse(p.stub,OFFLINE_NOTICE_MS+1000);
 let calls=0;await mailbox(p.stub,{send:async()=>{calls++;throw Error('provider down')}});
 await fire(p.stub);
 let s=await state(p.stub);expect(calls).toBe(1);expect(s.notified).toBeUndefined();expect(s.attempts).toBe('1');
 expect(Number(s.notifyAt)-Date.now()).toBeGreaterThan(14*60000);expect(s.alarm).toBe(Number(s.notifyAt));
 for(let n=0;n<2;n++){await runInDurableObject(p.stub,async o=>{o.put('offline_notify_at',Date.now()-1);await o.alarm()})}
 s=await state(p.stub);expect(calls).toBe(3);expect(s.notified).toBe('1');
 await fire(p.stub);expect(calls).toBe(3);
});

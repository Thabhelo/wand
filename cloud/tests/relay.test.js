import {env} from 'cloudflare:workers';
import {runInDurableObject,evictDurableObject,runDurableObjectAlarm} from 'cloudflare:test';
import {beforeAll,beforeEach,expect,it,vi} from 'vitest';
import connectionsMigration from '../migrations/0002_connections.sql?raw';
import migration from '../migrations/0001_registry.sql?raw';
import worker from '../src/index.js';
import {envelope,token,validate} from '../src/common.js';
vi.mock('../src/auth.js',async()=>{const {Failure}=await import('../src/common.js');return {authenticate:async r=>{const user=r.headers.get('Authorization')?.slice(7);if(!['alice','bob'].includes(user))throw new Failure('unauthorized',401);return {user_id:user,client_id:'test-client'}}}});
let ip;
beforeAll(async()=>{for(const sql of (migration+connectionsMigration).split(';').filter(s=>s.trim()))await env.DB.prepare(sql).run()});
beforeEach(async()=>{ip=crypto.randomUUID();for(const table of ['connections','consent_requests','tokens','pairing','devices','deleting'])await env.DB.prepare('DELETE FROM '+table).run()});
function request(path,method='GET',data,who='alice'){return worker.fetch(new Request('https://api.example'+path,{method,headers:{Authorization:'Bearer '+who,'CF-Connecting-IP':ip,'Content-Type':'application/json'},body:data?JSON.stringify(data):undefined}),env)}
async function pair(){const r=await request('/v1/pairing/code','POST',{kind:'mac',device_name:'Test Mac',agent_version:'0.8.0'});expect(r.status).toBe(200);const p=await r.json(),raw=token();expect((await request('/v1/pairing/redeem','POST',{device_token:raw},p.bootstrap_token)).status).toBe(409);expect((await request('/v1/pairing/claim','POST',{code:p.code})).status).toBe(200);expect((await request('/v1/pairing/redeem','POST',{device_token:raw},p.bootstrap_token)).status).toBe(200);return {...p,raw,stub:env.DEVICES.getByName(p.device_id)}}
function inbox(ws){const queue=[],waiters=[];ws.addEventListener('message',e=>{const v=JSON.parse(e.data),waiter=waiters.shift();if(waiter)waiter(v);else queue.push(v)});return ()=>queue.length?Promise.resolve(queue.shift()):new Promise(r=>waiters.push(r))}
// Hello establishes heartbeat freshness. Do not queue a second heartbeat behind ready:
// it races tests that deliberately expire the timestamp after the handshake.
async function connect(p,capabilities){const r=await worker.fetch(new Request('https://api.example/v1/ws/device',{headers:{Upgrade:'websocket','X-Wand-Device-ID':p.device_id,'CF-Connecting-IP':ip}}),env);expect(r.status).toBe(101);const ws=r.webSocket;ws.accept();const next=inbox(ws);ws.send(JSON.stringify(envelope('hello',{device_token:p.raw,agent_version:'0.8.0',device_name:'Test Mac',macos_version:'26',...(capabilities?{capabilities}:{})})));expect((await next()).type).toBe('ready');return {ws,next}}
async function poll(cid){for(let n=0;n<30;n++){const r=await(await request('/v1/commands/'+cid)).json();if(['succeeded','failed'].includes(r.status))return r;await new Promise(r=>setTimeout(r,10))}throw Error('No result')}
it('pairs, dispatches, returns a result and redacts cloud audit',async()=>{const p=await pair(),{ws,next}=await connect(p);const r=await request('/v1/commands','POST',{device_id:p.device_id,action:'open_url',params:{url:'https://example.com/private'}});expect(r.status).toBe(202);const {command_id}=await r.json();expect((await next()).params.url).toContain('private');ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data:{}})));expect((await poll(command_id)).status).toBe('succeeded');const a=await runInDurableObject(p.stub,o=>o.sql.exec('SELECT * FROM audit').toArray());expect(a.length).toBe(2);expect(JSON.stringify(a)).not.toContain('/private');ws.close()});
it('isolates accounts and fails fast offline',async()=>{const p=await pair(),data={device_id:p.device_id,action:'get_state',params:{}};expect((await request('/v1/commands','POST',data,'bob')).status).toBe(404);const r=await request('/v1/commands','POST',data);expect(r.status).toBe(409);expect((await r.json()).error.code).toBe('device_offline');expect((await request('/v1/devices','GET',undefined,'bad')).status).toBe(401)});
it('rejects shell injection and invalid params',async()=>{const p=await pair();for(const [action,params]of [['shell',{command:'whoami'}],['open_url',{url:'file:///etc/passwd'}],['set_volume',{level:101}],['quit_app',{app_name:'Finder',shell:'whoami'}]])expect((await request('/v1/commands','POST',{device_id:p.device_id,action,params})).status).toBe(422)});
it('pairing is single use and binds only one token',async()=>{const p=await pair();expect((await request('/v1/pairing/claim','POST',{code:p.code})).status).toBe(409);expect((await request('/v1/pairing/redeem','POST',{device_token:token()},p.bootstrap_token)).status).toBe(409);expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM tokens').first()).n).toBe(1);expect(JSON.stringify((await env.DB.prepare('SELECT * FROM tokens').all()).results)).not.toContain(p.raw)});
it('revokes the socket and invalidates its token',async()=>{const p=await pair(),{ws,next}=await connect(p);const closed=new Promise(r=>ws.addEventListener('close',r));expect((await request('/v1/devices/'+p.device_id,'DELETE')).status).toBe(200);expect((await next()).type).toBe('revoke');expect((await closed).code).toBe(4003);expect((await env.DB.prepare('SELECT revoked_at FROM tokens').first()).revoked_at).toBeTruthy();expect((await p.stub.presence()).online).toBe(false)});
it('recovers the socket across hibernation',async()=>{const p=await pair(),{ws,next}=await connect(p);await evictDurableObject(p.stub);expect((await p.stub.presence()).online).toBe(true);expect((await request('/v1/commands','POST',{device_id:p.device_id,action:'mute',params:{}})).status).toBe(202);expect((await next()).action).toBe('mute');ws.close()});
it('expires a missing heartbeat',async()=>{const p=await pair(),{ws}=await connect(p);await runInDurableObject(p.stub,o=>o.put('heartbeat',Date.now()-76000));expect((await p.stub.presence()).online).toBe(false);await runDurableObjectAlarm(p.stub);expect((await request('/v1/commands','POST',{device_id:p.device_id,action:'mute',params:{}})).status).toBe(409);ws.close()});
it('account deletion closes sockets and purges records',async()=>{const p=await pair(),{ws,next}=await connect(p);expect((await request('/v1/account','DELETE')).status).toBe(200);expect((await next()).type).toBe('revoke');expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM devices').first()).n).toBe(0);expect((await env.DB.prepare('SELECT COUNT(*) AS n FROM tokens').first()).n).toBe(0);expect(await runInDurableObject(p.stub,o=>o.sql.exec('SELECT COUNT(*) AS n FROM audit').one().n)).toBe(0);ws.close()});
it('self revoke invalidates server credentials',async()=>{const p=await pair(),{ws,next}=await connect(p);ws.send(JSON.stringify(envelope('revoke_self')));expect((await next()).type).toBe('revoke');expect((await env.DB.prepare('SELECT revoked_at FROM tokens').first()).revoked_at).toBeTruthy();ws.close()});
it('cancels pairing even after a token was redeemed',async()=>{const p=await pair(),{ws,next}=await connect(p);expect((await request('/v1/pairing/cancel','POST',{},p.bootstrap_token)).status).toBe(200);expect((await next()).type).toBe('revoke');expect((await env.DB.prepare('SELECT revoked_at FROM tokens').first()).revoked_at).toBeTruthy();ws.close()});
it('expires a dispatched command and records a timeout',async()=>{const p=await pair(),{ws,next}=await connect(p);const {command_id}=await(await request('/v1/commands','POST',{device_id:p.device_id,action:'mute',params:{}})).json();await next();await runInDurableObject(p.stub,o=>o.sql.exec('UPDATE commands SET created=created-16000').toArray());const r=await(await request('/v1/commands/'+command_id)).json();expect(r.status).toBe('failed');expect(r.error.code).toBe('command_timeout');ws.close()});
it('refuses state details from a locked Mac',async()=>{const p=await pair(),{ws,next}=await connect(p);const {command_id}=await(await request('/v1/commands','POST',{device_id:p.device_id,action:'get_state',params:{}})).json();await next();ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data:{screen_locked:true,frontmost_app:'secret'}})));expect((await poll(command_id)).status).toBe('failed');ws.close()});
it('fences old commands on a second authenticated socket',async()=>{const p=await pair(),a=await connect(p);const {command_id}=await(await request('/v1/commands','POST',{device_id:p.device_id,action:'mute',params:{}})).json();await a.next();const b=await connect(p);expect((await poll(command_id)).error.code).toBe('device_reconnected');expect((await p.stub.presence()).online).toBe(true);a.ws.close();b.ws.close()});
it('never lets a bad hello interrupt an authenticated command',async()=>{const p=await pair(),a=await connect(p);const {command_id}=await(await request('/v1/commands','POST',{device_id:p.device_id,action:'mute',params:{}})).json();await a.next();const response=await worker.fetch(new Request('https://api.example/v1/ws/device',{headers:{Upgrade:'websocket','X-Wand-Device-ID':p.device_id,'CF-Connecting-IP':ip}}),env);const bad=response.webSocket;bad.accept();const closed=new Promise(r=>bad.addEventListener('close',r));bad.send(JSON.stringify(envelope('heartbeat')));await closed;a.ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data:{}})));expect((await poll(command_id)).status).toBe('succeeded');a.ws.close()});
it('bounds hello attempts per IP',async()=>{for(let i=0;i<10;i++)expect((await worker.fetch(new Request('https://api.example/v1/ws/device',{headers:{Upgrade:'websocket','CF-Connecting-IP':ip}}),env)).status).toBe(400);expect((await worker.fetch(new Request('https://api.example/v1/ws/device',{headers:{Upgrade:'websocket','CF-Connecting-IP':ip}}),env)).status).toBe(429)});

it('serves connector discovery before requiring a user login',async()=>{const response=await request('/openapi.json','GET',undefined,'not-a-user');expect(response.status).toBe(200);const spec=await response.json();expect(spec.info.title).toBe('Wand device control API');expect(spec.paths['/v1/commands']).toBeDefined()});
it('routes desktop observations without retaining their contents in audit',async()=>{
 const p=await pair(),{ws,next}=await connect(p);
 const accepted=await request('/v1/commands','POST',{device_id:p.device_id,action:'desktop_observe',params:{bundle_id:'com.apple.finder'}});expect(accepted.status).toBe(202);
 const {command_id}=await accepted.json();expect((await next()).action).toBe('desktop_observe');
 const data={snapshot_id:crypto.randomUUID(),bundle_id:'com.apple.finder',expires_at:new Date(Date.now()+30000).toISOString(),elements:[{element_id:'0',role:'AXWindow',label:'private window text',actions:[]}],truncated:false};
 ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data})));
 expect((await poll(command_id)).result).toEqual(data);
 const audit=await runInDurableObject(p.stub,o=>o.sql.exec('SELECT * FROM audit').toArray());expect(JSON.stringify(audit)).not.toContain('private window text');ws.close();
});
it('rejects malformed desktop input before it can reach a device',async()=>{
 const p=await pair();for(const params of [
 {operation:'type',text:'hello',element_id:'0'},
 {snapshot_id:crypto.randomUUID(),operation:'shell',text:'whoami'},
 {snapshot_id:crypto.randomUUID(),operation:'click',x:-1,y:0},
 {snapshot_id:crypto.randomUUID(),operation:'key',key:'command+q'}
 ])expect((await request('/v1/commands','POST',{device_id:p.device_id,action:'desktop_act',params})).status).toBe(422);
});
it('returns an app inventory only to its owner and keeps its contents out of audit',async()=>{
 const p=await pair(),{ws,next}=await connect(p);
 const body={device_id:p.device_id,action:'list_apps',params:{offset:0}};
 expect((await request('/v1/commands','POST',body,'bob')).status).toBe(404);
 const accepted=await request('/v1/commands','POST',body);expect(accepted.status).toBe(202);
 const {command_id}=await accepted.json();expect((await next()).action).toBe('list_apps');
 const data={apps:[{name:'Private Test App',bundle_id:'test.private.app',last_opened:null,running:false}],next_offset:null};
 ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data})));
 expect((await poll(command_id)).result).toEqual(data);
 const audit=await runInDurableObject(p.stub,o=>o.sql.exec('SELECT * FROM audit').toArray());
 expect(JSON.stringify(audit)).not.toContain('Private Test App');ws.close();
});
it('blocks session components before dispatch, including manual names',async()=>{const p=await pair();for(const params of [{bundle_id:'com.apple.loginwindow'},{app_name:'Dock'},{app_name:'SystemUIServer.app'}]){const r=await request('/v1/commands','POST',{device_id:p.device_id,action:'quit_app',params});expect(r.status).toBe(403);expect((await r.json()).error.code).toBe('protected_app')}});
it('accepts precise app results and audio readings without admitting unrelated data',async()=>{const p=await pair(),{ws,next}=await connect(p);for(const [action,params,data]of [['quit_app',{bundle_id:'com.apple.TextEdit'},{already_closed:true}],['open_app',{bundle_id:'com.apple.TextEdit'},{already_open:true,focused:true}],['get_state',{}, {screen_locked:false,frontmost_app:null,now_playing:null,battery:null,running_apps:[],audio:{volume:60,muted:true}}]]){const r=await request('/v1/commands','POST',{device_id:p.device_id,action,params});const {command_id}=await r.json();await next();ws.send(JSON.stringify(envelope('result',{command_id,ok:true,data})));expect((await poll(command_id)).result).toEqual(data)}ws.close()});

const capabilityReport={schema_version:1,agent_version:'0.13.0',agent_build:'33',actions:['get_state','mute'],features:['audio_output_state'],permissions:{desktop_control:'denied',accessibility:'granted',screen_recording:'denied'}};
it('reports unknown for legacy peers and does not infer features from the version',async()=>{
 const p=await pair(),{ws}=await connect(p);
 const r=await request('/v1/devices/'+p.device_id+'/capabilities');expect(r.status).toBe(200);
 const c=await r.json();validate('DeviceCapabilities',c);expect(c.source).toBe('unknown');expect(c.features.audio_output_state).toBe('unknown');expect(c.actions.every(a=>a.support==='unknown')).toBe(true);expect(c.stale).toBe(true);ws.close();
});
it('reports declared support, survives eviction, rejects unsupported commands and fences reconnects',async()=>{
 const p=await pair(),a=await connect(p,capabilityReport),path='/v1/devices/'+p.device_id+'/capabilities';
 expect((await request(path,'GET',undefined,'bob')).status).toBe(404);
 let c=await(await request(path)).json();validate('DeviceCapabilities',c);expect(c.source).toBe('device');expect(c.permissions.accessibility).toBe('granted');expect(c.features.playback_state).toBe('unsupported');
 await evictDurableObject(p.stub);expect((await(await request(path)).json()).agent_build).toBe('33');
 const denied=await request('/v1/commands','POST',{device_id:p.device_id,action:'open_app',params:{app_name:'TextEdit'}});expect(denied.status).toBe(409);expect((await denied.json()).error.code).toBe('action_unsupported');
 const b=await connect(p);c=await(await request(path)).json();expect(c.source).toBe('unknown');a.ws.close();b.ws.close();
});
it('refreshes permission reports on heartbeat and hides stale permissions offline',async()=>{
 const p=await pair(),{ws}=await connect(p,capabilityReport),path='/v1/devices/'+p.device_id+'/capabilities';
 ws.send(JSON.stringify(envelope('heartbeat',{capabilities:{...capabilityReport,permissions:{desktop_control:'granted',accessibility:'denied',screen_recording:'unknown'}}})));
 for(let i=0;i<30;i++){if((await(await request(path)).json()).permissions.accessibility==='denied')break;await new Promise(r=>setTimeout(r,10))}
 expect((await(await request(path)).json()).permissions.accessibility).toBe('denied');
 await runInDurableObject(p.stub,o=>o.put('heartbeat',Date.now()-80000));
 const stale=await(await request(path)).json();expect(stale.stale).toBe(true);expect(stale.permissions.accessibility).toBe('unknown');expect(stale.actions.find(a=>a.name==='mute').support).toBe('supported');ws.close();
});
it('rejects unrecognized actions in a capability advertisement',async()=>{
 const {validate}=await import('../src/common.js');expect(()=>validate('DeviceMessage',envelope('hello',{device_token:token(),agent_version:'test',device_name:'Mac',macos_version:'26',capabilities:{...capabilityReport,actions:['shell']}}))).toThrow();
});

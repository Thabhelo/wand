import {env} from 'cloudflare:workers';
import {createExecutionContext,waitOnExecutionContext} from 'cloudflare:test';
import {getOAuthApi} from '@cloudflare/workers-oauth-provider';
import {beforeAll,beforeEach,expect,it,vi} from 'vitest';
import migration from '../migrations/0001_registry.sql?raw';
import connectionsMigration from '../migrations/0002_connections.sql?raw';
import worker,{options} from '../src/entry.js';
import {token} from '../src/common.js';
vi.mock('../src/auth.js',async()=>{const {Failure}=await import('../src/common.js');return {authenticate:async r=>{const user=r.headers.get('Authorization')?.slice(7);if(!['alice','bob'].includes(user))throw new Failure('unauthorized',401);return {user_id:user,client_id:'wand-dashboard'}}}});
let bindings,helpers,client,did,other,verifier,challenge;
beforeAll(async()=>{for(const sql of (migration+connectionsMigration).split(';').filter(s=>s.trim()))await env.DB.prepare(sql).run()});
beforeEach(async()=>{
 for(const table of ['connections','consent_requests','tokens','pairing','devices','deleting'])await env.DB.prepare('DELETE FROM '+table).run();
 bindings={...env};helpers=getOAuthApi(options,bindings);
 client=await helpers.createClient({clientName:'Muse test peer',redirectUris:['https://muse.example/callback'],tokenEndpointAuthMethod:'none',grantTypes:['authorization_code','refresh_token'],responseTypes:['code']});bindings.MUSE_CLIENT_IDS=client.clientId;
 did=crypto.randomUUID();other=crypto.randomUUID();for(const d of [did,other])await env.DB.prepare('INSERT INTO devices VALUES(?,?,?,?,?,?,?,NULL)').bind(d,'alice','mac','Test Mac','test',null,new Date().toISOString()).run();
 verifier=token();challenge=btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
});
async function request(path,method='GET',data,who='alice'){
 const ctx=createExecutionContext();const response=await worker.fetch(new Request('https://api.getwand.app'+path,{method,headers:{Authorization:'Bearer '+who,'Content-Type':data instanceof URLSearchParams?'application/x-www-form-urlencoded':'application/json','CF-Connecting-IP':crypto.randomUUID()},body:data instanceof URLSearchParams?data.toString():data?JSON.stringify(data):undefined}),bindings,ctx);await waitOnExecutionContext(ctx);return response;
}
async function begin(extra={}){
 const params=new URLSearchParams({client_id:client.clientId,response_type:'code',redirect_uri:'https://muse.example/callback',scope:'wand:get_state wand:mute',state:token(),code_challenge:challenge,code_challenge_method:'S256',resource:'https://api.getwand.app/connector',...extra});
 return request('/authorize?'+params);
}
async function approve(){const response=await begin();expect(response.status).toBe(302);const id=new URL(response.headers.get('Location')).searchParams.get('authorize');expect((await request('/v1/connections/consent?id='+id)).status).toBe(200);const approved=await request('/v1/connections/consent','POST',{id,decision:'allow',device_ids:[did],actions:['mute']});expect(approved.status).toBe(200);const code=new URL((await approved.json()).redirectTo).searchParams.get('code');return {id,code}}
async function exchange(code,codeVerifier=verifier){return request('/oauth/token','POST',new URLSearchParams({grant_type:'authorization_code',client_id:client.clientId,redirect_uri:'https://muse.example/callback',code,code_verifier:codeVerifier,resource:'https://api.getwand.app/connector'}))}
it('separates Firebase dashboard sessions from connector tokens',async()=>{expect((await request('/connector/v1/devices')).status).toBe(401);expect((await request('/v1/devices','GET',undefined,'bogus')).status).toBe(401)});
it('requires registered client, exact redirect, PKCE and known scopes',async()=>{
 for(const extra of [{client_id:'unregistered'},{redirect_uri:'https://attacker.invalid/'},{code_challenge_method:'plain'},{scope:'wand:shell'},{resource:'https://other.invalid'},{state:''}])expect((await begin(extra)).status).toBeGreaterThanOrEqual(400);
});
it('binds review to the signed-in user and prevents privilege widening',async()=>{
 const response=await begin(),id=new URL(response.headers.get('Location')).searchParams.get('authorize');expect((await request('/v1/connections/consent?id='+id)).status).toBe(200);
 expect((await request('/v1/connections/consent?id='+id,'GET',undefined,'bob')).status).toBe(410);
 expect((await request('/v1/connections/consent','POST',{id,decision:'allow',device_ids:[did],actions:['run_shortcut']})).status).toBe(403);
 expect((await request('/v1/connections/consent','POST',{id,decision:'allow',device_ids:[crypto.randomUUID()],actions:['mute']})).status).toBe(404);
});
it('exchanges a real code and enforces device, action, admin and revoke boundaries',async()=>{
 const {id,code}=await approve(),response=await exchange(code);expect(response.status).toBe(200);const credentials=await response.json();expect(credentials.access_token).toBeTruthy();
 expect((await request('/v1/connections/consent','POST',{id,decision:'allow',device_ids:[did],actions:['mute']})).status).toBe(410);
 const bearer=credentials.access_token;
 const caps=await request('/connector/v1/devices/'+did+'/capabilities','GET',undefined,bearer);expect(caps.status).toBe(200);const report=await caps.json();expect(report.actions.find(a=>a.name==='mute').authorized).toBe(true);expect(report.actions.find(a=>a.name==='get_state').authorized).toBe(false);
 expect((await request('/connector/v1/devices/'+other+'/capabilities','GET',undefined,bearer)).status).toBe(404);
 expect((await request('/connector/v1/devices/'+did+'/capabilities','GET',undefined,'alice')).status).toBe(401);

 expect((await(await request('/connector/v1/devices','GET',undefined,bearer)).json()).map(d=>d.device_id)).toEqual([did]);
 expect((await request('/connector/v1/account','DELETE',undefined,bearer)).status).toBe(404);
 expect((await request('/v1/devices','GET',undefined,bearer)).status).toBe(401);
 for(const body of [{device_id:other,action:'mute',params:{}},{device_id:did,action:'get_state',params:{}}])expect((await request('/connector/v1/commands','POST',body,bearer)).status).toBe(403);
 expect((await request('/connector/v1/commands','POST',{device_id:did,action:'mute',params:{}},bearer)).status).toBe(409);
 const grants=await(await request('/v1/connections')).json();expect(grants).toHaveLength(1);
 await request('/v1/connections/'+grants[0].id,'DELETE');expect((await request('/connector/v1/devices','GET',undefined,bearer)).status).toBe(401);
});
it('rejects incorrect PKCE and expired consent',async()=>{
 const {code}=await approve();expect((await exchange(code,token())).status).toBe(400);
 const response=await begin(),id=new URL(response.headers.get('Location')).searchParams.get('authorize');await env.DB.prepare('UPDATE consent_requests SET expires_at=0 WHERE id=?').bind(id).run();expect((await request('/v1/connections/consent?id='+id)).status).toBe(410);
});
it('account deletion invalidates existing connector access',async()=>{
 const {code}=await approve(),credentials=await(await exchange(code)).json();expect((await request('/v1/account','DELETE')).status).toBe(200);expect((await request('/connector/v1/devices','GET',undefined,credentials.access_token)).status).toBe(401);expect((await env.DB.prepare('SELECT COUNT(*) n FROM connections').first()).n).toBe(0);
});

it('rejects authorization code replay and invalidates its grant',async()=>{const {code}=await approve();const credentials=await(await exchange(code)).json();expect(credentials.access_token).toBeTruthy();expect((await exchange(code)).status).toBe(400);expect((await request('/connector/v1/devices','GET',undefined,credentials.access_token)).status).toBe(401)});
it('keeps refreshed token scopes narrower than the connection grant',async()=>{
 const response=await begin(),id=new URL(response.headers.get('Location')).searchParams.get('authorize');
 const approved=await request('/v1/connections/consent','POST',{id,decision:'allow',device_ids:[did],actions:['mute','get_state']});
 const code=new URL((await approved.json()).redirectTo).searchParams.get('code'),credentials=await(await exchange(code)).json();
 const refreshed=await request('/oauth/token','POST',new URLSearchParams({grant_type:'refresh_token',client_id:client.clientId,refresh_token:credentials.refresh_token,scope:'wand:get_state',resource:'https://api.getwand.app/connector'}));expect(refreshed.status).toBe(200);
 const bearer=(await refreshed.json()).access_token;
 expect((await request('/connector/v1/commands','POST',{device_id:did,action:'mute',params:{}},bearer)).status).toBe(403);
 expect((await request('/connector/v1/commands','POST',{device_id:did,action:'get_state',params:{}},bearer)).status).toBe(409);
});
it('declining creates no grant and returns the exact registered callback',async()=>{
 const response=await begin(),id=new URL(response.headers.get('Location')).searchParams.get('authorize');
 const declined=await request('/v1/connections/consent','POST',{id,decision:'deny'});expect(declined.status).toBe(200);const target=new URL((await declined.json()).redirectTo);expect(target.origin).toBe('https://muse.example');expect(target.searchParams.get('error')).toBe('access_denied');expect((await env.DB.prepare('SELECT COUNT(*) n FROM connections').first()).n).toBe(0);
});

it('existing narrow grants cannot acquire desktop access',async()=>{
 const {code}=await approve(),credentials=await(await exchange(code)).json();
 const r=await request('/connector/v1/commands','POST',{device_id:did,action:'desktop_observe',params:{bundle_id:'com.apple.finder'}},credentials.access_token);expect(r.status).toBe(403);
});
it('refuses tokens refreshed after revocation even while the OAuth grant still exists',async()=>{
 // Simulates the KV delay: the D1 connection is revoked but the stored grant has not been removed yet.
 const {code}=await approve(),first=await (await exchange(code)).json();
 expect((await request('/connector/v1/devices','GET',undefined,first.access_token)).status).toBe(200);
 await env.DB.prepare('UPDATE connections SET revoked_at=? WHERE user_id=?').bind(new Date().toISOString(),'alice').run();
 const refreshed=await request('/oauth/token','POST',new URLSearchParams({grant_type:'refresh_token',client_id:client.clientId,refresh_token:first.refresh_token}));
 expect(refreshed.status).toBe(200);const next=await refreshed.json();expect(next.access_token).toBeTruthy();
 for(const path of ['/connector/v1/devices','/connector/v1/devices/'+did+'/capabilities'])expect((await request(path,'GET',undefined,next.access_token)).status).toBe(401);
 expect((await request('/connector/v1/commands','POST',{device_id:did,action:'mute',params:{}},next.access_token)).status).toBe(401);
 expect((await request('/connector/v1/devices','GET',undefined,first.access_token)).status).toBe(401);
});

import {DurableObject} from 'cloudflare:workers';
import {authenticate} from './auth.js';
import {connections,revokeOAuthGrants} from './connections.js';
import {publicSpec} from './openapi.js';
import {Failure,body,envelope,failure,hash,id,json,stamp,token} from './common.js';
export {Device} from './device.js';
export {Cleanup} from './cleanup.js';
export class RateLimit extends DurableObject{
 constructor(ctx,env){super(ctx,env);ctx.storage.sql.exec('CREATE TABLE IF NOT EXISTS hits(t INTEGER NOT NULL)')}
 async take(limit,period){const sql=this.ctx.storage.sql;sql.exec('DELETE FROM hits WHERE t <= ?',Date.now()-period);if(sql.exec('SELECT COUNT(*) AS n FROM hits').one().n>=limit)return false;sql.exec('INSERT INTO hits VALUES(?)',Date.now());await this.ctx.storage.setAlarm(Date.now()+period+1000);return true}
 async alarm(){this.ctx.storage.sql.exec('DELETE FROM hits')}
}
const row=(env,sql,...args)=>env.DB.prepare(sql).bind(...args).first();
async function limit(env,key,max,period=60000){if(!await env.LIMITS.getByName(await hash(key)).take(max,period))throw new Failure('rate_limited',429)}
async function user(request,env,principal){const p=principal||await authenticate(request,env);if(!(request.method==='DELETE'&&new URL(request.url).pathname==='/v1/account')&&await row(env,'SELECT user_id FROM deleting WHERE user_id=?',p.user_id))throw new Failure('account_deletion_pending',409);return p}
async function owned(env,did,uid){const d=await row(env,'SELECT * FROM devices WHERE id=? AND user_id=? AND revoked_at IS NULL',did,uid);if(!d)throw new Failure('device_not_found',404);return d}
async function revoke(env,did){await env.DB.batch([env.DB.prepare('UPDATE devices SET revoked_at=? WHERE id=?').bind(stamp(),did),env.DB.prepare('UPDATE tokens SET revoked_at=? WHERE device_id=?').bind(stamp(),did),env.DB.prepare('DELETE FROM pairing WHERE device_id=?').bind(did)]);await env.DEVICES.getByName(did).revoke()}
async function publicDevice(env,d){const state=await env.DEVICES.getByName(d.id).presence();return {device_id:d.id,name:d.name,kind:d.kind,online:state.online,last_seen:state.last_seen||d.last_seen}}
export default{
 async fetch(request,env,ctx,principal){try{const url=new URL(request.url),path=url.pathname,method=request.method,ip=request.headers.get('CF-Connecting-IP')||'local';
  if(path==='/openapi.json'&&method==='GET')return json(publicSpec(env));
  if(path==='/healthz'&&method==='GET'){const cleanup=await env.CLEANUP.getByName('registry').ensure();const healthy=!cleanup.failures&&(!cleanup.last_success||Date.now()-cleanup.last_success<3*60*60*1000);return json({status:healthy?'ok':'degraded',cleanup},healthy?200:503)}
  if(path==='/config'&&method==='GET')return json({facebookEnabled:env.FACEBOOK_ENABLED==='true',firebase:{apiKey:env.FIREBASE_API_KEY,authDomain:env.FIREBASE_AUTH_DOMAIN,projectId:env.FIREBASE_PROJECT_ID,appId:env.FIREBASE_APP_ID}});
  if(path==='/v1/ws/device'){
   await limit(env,'hello:'+ip,10);
   // A public device ID routes the socket; only the protocol hello grants access.
   const did=request.headers.get('X-Wand-Device-ID');if(!did||!/^[0-9a-f-]{36}$/i.test(did))throw new Failure('device_id_required',400);
   if(request.headers.get('Upgrade')?.toLowerCase()!=='websocket')throw new Failure('websocket_required',426);
   if(!await row(env,'SELECT id FROM devices WHERE id=? AND revoked_at IS NULL',did)){
    const pair=new WebSocketPair();pair[1].accept();pair[1].close(4003,'device_token_revoked');return new Response(null,{status:101,webSocket:pair[0]})
   }
   return env.DEVICES.getByName(did).fetch(request);
  }
  if(path==='/v1/pairing/code'&&method==='POST'){
   await limit(env,'enroll:'+ip,5);const b=await body(request,'PairingCodeRequest');await env.CLEANUP.getByName('registry').ensure();const did=id(),bootstrap=token(),bootstrapHash=await hash(bootstrap),deadline=Date.now()+600000;
   const alphabet='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';let code;
   for(let n=0;n<5;n++){code=Array.from(crypto.getRandomValues(new Uint8Array(6)),v=>alphabet[v%alphabet.length]).join('');if(!await row(env,'SELECT code FROM pairing WHERE code=?',code))break;if(n===4)throw new Failure('pairing_busy',503)}
   await env.DB.batch([env.DB.prepare('INSERT INTO devices VALUES(?,NULL,?,?,?,?,?,NULL)').bind(did,b.kind,b.device_name,b.agent_version,null,stamp()),env.DB.prepare('INSERT INTO pairing VALUES(?,?,?,?,NULL,NULL)').bind(code,did,bootstrapHash,deadline)]);
   return json({device_id:did,code,bootstrap_token:bootstrap,expires_at:stamp(deadline)});
  }
  if(['/v1/pairing/redeem','/v1/pairing/cancel'].includes(path)&&method==='POST'){
   await limit(env,'redeem:'+ip,60);const cancel=path.endsWith('/cancel');const b=await body(request,cancel?'PairingCancelRequest':'PairingRedeemRequest');const auth=request.headers.get('Authorization')||'';if(!auth.startsWith('Bearer '))throw new Failure('unauthorized',401);const p=await row(env,'SELECT * FROM pairing WHERE bootstrap_hash=?',await hash(auth.slice(7)));if(!p||p.deadline<Date.now())throw new Failure('pairing_expired',410);
   if(cancel){await revoke(env,p.device_id);return json({status:'cancelled'})}
   if(!p.claimed_at)throw new Failure('pairing_pending',409);const h=await hash(b.device_token);
   const statements=[env.DB.prepare('UPDATE pairing SET redeemed_hash=? WHERE code=? AND (redeemed_hash IS NULL OR redeemed_hash=?) AND deadline>? AND EXISTS(SELECT 1 FROM devices WHERE id=pairing.device_id AND revoked_at IS NULL)').bind(h,p.code,h,Date.now()),env.DB.prepare('INSERT OR IGNORE INTO tokens SELECT ?,device_id,?,NULL FROM pairing WHERE code=? AND redeemed_hash=? AND EXISTS(SELECT 1 FROM devices WHERE id=pairing.device_id AND revoked_at IS NULL)').bind(h,stamp(),p.code,h)];
   const results=await env.DB.batch(statements);if(!results[0].meta.changes)throw new Failure('pairing_already_redeemed',409);return json({device_id:p.device_id,status:'paired'});
  }
  const u=await user(request,env,principal);
  if(!principal&&path.startsWith('/v1/connections')){const response=await connections(request,env,u);if(response)return response;}
  if(['/v1/pairing/preview','/v1/pairing/claim'].includes(path)&&method==='POST'){
   await limit(env,'claim:'+ip,5);const b=await body(request,'PairingClaimRequest');const p=await row(env,'SELECT pairing.*,devices.name FROM pairing JOIN devices ON devices.id=pairing.device_id WHERE code=? AND claimed_at IS NULL AND deadline>? AND revoked_at IS NULL',b.code,Date.now());if(!p)throw new Failure('pairing_code_invalid',409);
   if(path.endsWith('/preview'))return json({device_name:p.name,expires_at:stamp(p.deadline)});
   const marker=stamp()+':'+id();const results=await env.DB.batch([env.DB.prepare('UPDATE pairing SET claimed_at=? WHERE code=? AND claimed_at IS NULL AND deadline>? AND NOT EXISTS(SELECT 1 FROM deleting WHERE user_id=?)').bind(marker,b.code,Date.now(),u.user_id),env.DB.prepare('UPDATE devices SET user_id=? WHERE id=? AND revoked_at IS NULL AND EXISTS(SELECT 1 FROM pairing WHERE device_id=devices.id AND claimed_at=?)').bind(u.user_id,p.device_id,marker)]);if(!results[0].meta.changes)throw new Failure('pairing_code_invalid',409);return json({device_id:p.device_id,status:'claimed'});
  }
  if(path==='/v1/devices'&&method==='GET'){const {results}=await env.DB.prepare('SELECT * FROM devices WHERE user_id=? AND revoked_at IS NULL').bind(u.user_id).all();return json(await Promise.all(results.filter(d=>!u.device_ids||u.device_ids.includes(d.id)).map(d=>publicDevice(env,d))))}
  const devicePath=path.match(/^\/v1\/devices\/([0-9a-f-]{36})$/i);
  if(devicePath){const d=await owned(env,devicePath[1],u.user_id);if(method==='PATCH'){const b=await body(request,'RenameDeviceRequest');await env.DB.prepare('UPDATE devices SET name=? WHERE id=?').bind(b.name,d.id).run();return json(await publicDevice(env,{...d,name:b.name}))}if(method==='DELETE'){await revoke(env,d.id);return json({device_id:d.id,status:'revoked'})}}
  if(path==='/v1/commands'&&method==='POST'){const b=await body(request,'CommandRequest');if(u.device_ids&&(!u.device_ids.includes(b.device_id)||!u.actions.includes(b.action)))throw new Failure('action_not_authorized',403);const d=await owned(env,b.device_id,u.user_id);await limit(env,'commands:'+u.user_id,60);const result=await env.DEVICES.getByName(d.id).command({...b,...u,ip});return new Response(result.body,{status:result.status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}})}
  const commandPath=path.match(/^\/v1\/commands\/([0-9a-f-]{36})$/i);
  if(commandPath&&method==='GET'){
   // Device IDs are not encoded in command IDs: probe only the caller's bounded device list.
   const {results}=await env.DB.prepare('SELECT id FROM devices WHERE user_id=?').bind(u.user_id).all();for(const d of results){if(u.device_ids&&!u.device_ids.includes(d.id))continue;const result=await env.DEVICES.getByName(d.id).commandStatus(commandPath[1],u.user_id,u.actions?{actions:u.actions,client_id:u.client_id}:null);if(result)return new Response(result.body,{status:result.status,headers:{'Content-Type':'application/json','Cache-Control':'no-store'}})}throw new Failure('command_not_found',404)
  }
  if(path==='/v1/account'&&method==='DELETE'){
   await env.DB.prepare('INSERT OR IGNORE INTO deleting VALUES(?)').bind(u.user_id).run();
   await revokeOAuthGrants(env,u.user_id);
   await env.DB.batch([env.DB.prepare('DELETE FROM connections WHERE user_id=?').bind(u.user_id),env.DB.prepare('DELETE FROM consent_requests WHERE user_id=?').bind(u.user_id)]);
   await env.DB.batch([env.DB.prepare('UPDATE tokens SET revoked_at=? WHERE device_id IN (SELECT id FROM devices WHERE user_id=?)').bind(stamp(),u.user_id),env.DB.prepare('UPDATE devices SET revoked_at=? WHERE user_id=?').bind(stamp(),u.user_id)]);
   const {results}=await env.DB.prepare('SELECT id FROM devices WHERE user_id=?').bind(u.user_id).all();for(const d of results)await env.DEVICES.getByName(d.id).purge();
   await env.DB.batch([env.DB.prepare('DELETE FROM tokens WHERE device_id IN (SELECT id FROM devices WHERE user_id=?)').bind(u.user_id),env.DB.prepare('DELETE FROM pairing WHERE device_id IN (SELECT id FROM devices WHERE user_id=?)').bind(u.user_id),env.DB.prepare('DELETE FROM devices WHERE user_id=?').bind(u.user_id),env.DB.prepare('DELETE FROM deleting WHERE user_id=?').bind(u.user_id)]);return json({status:'deleted'});
  }
  throw new Failure('route_not_found',404);
 }catch(e){return failure(e)}}
};

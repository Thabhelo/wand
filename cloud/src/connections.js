import catalog from '../../contracts/actions.json' with {type:'json'};
import {Failure,json,token,stamp} from './common.js';
export const RESOURCE='https://api.getwand.app/connector';
export const SCOPES=catalog.map(a=>'wand:'+a.name);
export function trusted(env,clientId){return !!clientId&&(env.MUSE_CLIENT_IDS||'').split(',').filter(Boolean).includes(clientId)}
async function input(request){
 let size=0,text='';const decoder=new TextDecoder();if(request.body)for await(const chunk of request.body){size+=chunk.byteLength;if(size>8192)throw new Failure('invalid_request',422);text+=decoder.decode(chunk,{stream:true})}text+=decoder.decode();
 try{const value=JSON.parse(text);if(!value||typeof value!=='object'||Array.isArray(value))throw Error();return value}catch{throw new Failure('invalid_request',422)}
}
export async function revokeOAuthGrants(env,userId,connectionId=null){
 if(!env.OAUTH_PROVIDER)return;
 let cursor;do{const page=await env.OAUTH_PROVIDER.listUserGrants(userId,{limit:100,cursor});for(const grant of page.items)if(!connectionId||grant.metadata?.connection_id===connectionId)await env.OAUTH_PROVIDER.revokeGrant(grant.id,userId);cursor=page.cursor}while(cursor);
}
export async function beginConsent(request,env){
 const url=new URL(request.url);if(url.search.length>8192)throw new Failure('invalid_authorization_request',400);
 if(!trusted(env,url.searchParams.get('client_id')))throw new Failure('connector_not_registered',403);
 let req;try{req=await env.OAUTH_PROVIDER.parseAuthRequest(request)}catch{throw new Failure('invalid_authorization_request',400)}
 const callback=new URL(req.redirectUri);if(callback.protocol!=='https:'||callback.username||callback.password)throw new Failure('invalid_authorization_request',400);
 if(!trusted(env,req.clientId))throw new Failure('connector_not_registered',403);
 if(req.responseType!=='code'||req.codeChallengeMethod!=='S256'||!req.codeChallenge||!req.state||req.resource!==RESOURCE||!req.scope.length||req.scope.some(s=>!SCOPES.includes(s)))throw new Failure('invalid_authorization_request',400);
 const id=token();await env.DB.prepare('INSERT INTO consent_requests(id,request_json,expires_at) VALUES(?,?,?)').bind(id,JSON.stringify(req),Date.now()+600000).run();
 return new Response(null,{status:302,headers:{Location:'https://app.getwand.app/?authorize='+id,'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}});
}
export async function connections(request,env,user){
 const path=new URL(request.url).pathname;
 if(path==='/v1/connections'&&request.method==='GET'){
  const {results}=await env.DB.prepare('SELECT * FROM connections WHERE user_id=? AND revoked_at IS NULL').bind(user.user_id).all();
  return json(results.map(c=>({id:c.id,name:'Muse',device_ids:JSON.parse(c.device_ids),actions:JSON.parse(c.actions),created_at:c.created_at})));
 }
 const revoke=path.match(/^\/v1\/connections\/([A-Za-z0-9_-]+)$/);
 if(revoke&&request.method==='DELETE'){
  // D1 is authoritative on every request, including already-issued OAuth tokens.
  await env.DB.prepare('UPDATE connections SET revoked_at=? WHERE id=? AND user_id=?').bind(stamp(),revoke[1],user.user_id).run();await revokeOAuthGrants(env,user.user_id,revoke[1]);return json({status:'revoked'});
 }
 if(path!=='/v1/connections/consent'||!['GET','POST'].includes(request.method))return null;
 const b=request.method==='POST'?await input(request):{},id=new URL(request.url).searchParams.get('id')||b.id;
 if(typeof id!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(id))throw new Failure('consent_expired',410);
 await env.DB.prepare('UPDATE consent_requests SET user_id=? WHERE id=? AND user_id IS NULL AND used=0 AND expires_at>?').bind(user.user_id,id,Date.now()).run();
 const row=await env.DB.prepare('SELECT * FROM consent_requests WHERE id=? AND user_id=? AND used=0 AND expires_at>?').bind(id,user.user_id,Date.now()).first();
 if(!row)throw new Failure('consent_expired',410);
 const req=JSON.parse(row.request_json);if(!trusted(env,req.clientId))throw new Failure('connector_not_registered',403);
 if(request.method==='GET')return json({name:'Muse',actions:catalog.filter(a=>req.scope.includes('wand:'+a.name)).map(a=>({name:a.name,description:a.description,risk:a.risk}))});
 if(b.decision!=='allow'&&b.decision!=='deny')throw new Failure('invalid_request',422);
 let devices=[],actions=[];
 if(b.decision==='allow'){
  if(!Array.isArray(b.device_ids)||!b.device_ids.length||b.device_ids.length>20||!Array.isArray(b.actions)||!b.actions.length||b.actions.length>catalog.length)throw new Failure('invalid_request',422);
  devices=[...new Set(b.device_ids)];actions=[...new Set(b.actions)];
  if(actions.some(a=>typeof a!=='string'||!req.scope.includes('wand:'+a)))throw new Failure('action_not_authorized',403);
  for(const did of devices){if(typeof did!=='string'||!await env.DB.prepare('SELECT id FROM devices WHERE id=? AND user_id=? AND revoked_at IS NULL').bind(did,user.user_id).first())throw new Failure('device_not_found',404)}
 }
 const taken=await env.DB.prepare('UPDATE consent_requests SET used=1 WHERE id=? AND used=0 AND expires_at>? AND NOT EXISTS(SELECT 1 FROM deleting WHERE user_id=?)').bind(id,Date.now(),user.user_id).run();
 if(!taken.meta.changes)throw new Failure('consent_expired',410);
 if(b.decision==='deny'){const redirect=new URL(req.redirectUri);redirect.searchParams.set('error','access_denied');redirect.searchParams.set('state',req.state);redirect.searchParams.set('iss','https://api.getwand.app');return json({redirectTo:redirect.href})}
 const cid=token();
 const inserted=await env.DB.prepare('INSERT INTO connections SELECT ?,?,?,?,?,?,NULL WHERE NOT EXISTS(SELECT 1 FROM deleting WHERE user_id=?)').bind(cid,user.user_id,req.clientId,JSON.stringify(devices),JSON.stringify(actions),stamp(),user.user_id).run();
 if(!inserted.meta.changes)throw new Failure('account_deletion_pending',409);
 try{return json(await env.OAUTH_PROVIDER.completeAuthorization({request:req,userId:user.user_id,metadata:{name:'Muse',connection_id:cid},scope:actions.map(a=>'wand:'+a),props:{connection_id:cid,user_id:user.user_id,client_id:req.clientId},revokeExistingGrants:false}))}
 catch(e){await env.DB.prepare('DELETE FROM connections WHERE id=?').bind(cid).run();throw e}
}
export async function connectorPrincipal(env,props){
 if(!props?.connection_id||!trusted(env,props.client_id))throw new Failure('unauthorized',401);
 const c=await env.DB.prepare('SELECT * FROM connections WHERE id=? AND user_id=? AND client_id=? AND revoked_at IS NULL').bind(props.connection_id,props.user_id,props.client_id).first();
 if(!c)throw new Failure('connection_revoked',401);
 return {user_id:c.user_id,client_id:c.client_id,device_ids:JSON.parse(c.device_ids),actions:JSON.parse(c.actions).filter(a=>props.actions?.includes(a))};
}

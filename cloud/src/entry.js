import {OAuthProvider} from '@cloudflare/workers-oauth-provider';
import relay from './index.js';
import {beginConsent,connectorPrincipal,RESOURCE,SCOPES} from './connections.js';
import {failure,Failure,hash} from './common.js';
export {Device,RateLimit,Cleanup} from './index.js';
export const options={
 apiRoute:'/connector/',
 apiHandler:{async fetch(request,env,ctx){try{
  const url=new URL(request.url),path=url.pathname.slice('/connector'.length);
  if(!((request.method==='GET'&&(path==='/v1/devices'||/^\/v1\/commands\/[0-9a-f-]{36}$/i.test(path)))||(request.method==='POST'&&path==='/v1/commands')))throw new Failure('route_not_found',404);
  const principal=await connectorPrincipal(env,ctx.props);url.pathname=path;
  return relay.fetch(new Request(url,request),env,ctx,principal);
 }catch(e){return failure(e)}}},
 defaultHandler:{async fetch(request,env,ctx){try{
  if(new URL(request.url).pathname==='/authorize'){
   if(request.method!=='GET')throw new Failure('invalid_request',400);
   const ip=request.headers.get('CF-Connecting-IP')||'local';
   if(!await env.LIMITS.getByName(await hash('authorize:'+ip)).take(20,60000))throw new Failure('rate_limited',429);
   return await beginConsent(request,env);
  }
  return relay.fetch(request,env,ctx);
 }catch(e){return failure(e)}}},
 authorizeEndpoint:'/authorize',tokenEndpoint:'/oauth/token',
 tokenExchangeCallback:({props,requestedScope})=>({accessTokenProps:{...props,actions:requestedScope.filter(s=>s.startsWith('wand:')).map(s=>s.slice(5))}}),
 onError:()=>{},clientIdMetadataDocumentEnabled:false,
 accessTokenTTL:900,refreshTokenTTL:2592000,scopesSupported:SCOPES,
 allowPlainPKCE:false,allowImplicitFlow:false,
 resourceMetadata:{resource:RESOURCE,authorization_servers:['https://api.getwand.app'],scopes_supported:SCOPES,resource_name:'Wand Mac control'}
};
const provider=new OAuthProvider(options);
export default {
 fetch:(request,env,ctx)=>provider.fetch(request,env,ctx),
 // Compatibility only: Cloudflare currently rejects deleting the legacy cron at
 // the account limit. It may ensure the alarm, but never runs database cleanup.
 async scheduled(event,env){await env.CLEANUP.getByName('registry').ensure()}
};

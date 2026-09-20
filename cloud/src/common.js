import * as schemas from './contracts.js';
export const stamp=(n=Date.now())=>new Date(n).toISOString();
export const id=()=>crypto.randomUUID();
export const envelope=(type,fields={})=>({v:1,type,id:id(),ts:stamp(),...fields});
export const hash=async value=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value))),b=>b.toString(16).padStart(2,'0')).join('');
export function token(){const bytes=crypto.getRandomValues(new Uint8Array(32));return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','')}
export class Failure extends Error{constructor(code,status=400,extra={}){super(code.replaceAll('_',' '));this.code=code;this.status=status;this.extra=extra}}
export function validate(name,data){if(!schemas[name]?.(data))throw new Failure('invalid_request',422);return data}
export function json(data,status=200){return Response.json(data,{status,headers:{'Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Frame-Options':'DENY'}})}
export function failure(e){return json({error:{code:e instanceof Failure?e.code:'service_unavailable',message:e instanceof Failure?e.message:'Service temporarily unavailable',...(e.extra||{})}},e instanceof Failure?e.status:503)}
export async function body(request,name){let size=0;const chunks=[];if(request.body)for await(const chunk of request.body){size+=chunk.byteLength;if(size>65536)throw new Failure('request_too_large',413);chunks.push(chunk)}const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.byteLength}try{return validate(name,JSON.parse(new TextDecoder().decode(bytes)))}catch(e){if(e instanceof Failure)throw e;throw new Failure('invalid_request',422)}}

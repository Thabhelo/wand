import {createRemoteJWKSet,jwtVerify} from 'jose';
import {Failure} from './common.js';
const keysets=new Map();
export async function authenticate(request,env){
 if(!env.AUTH0_ISSUER||!env.AUTH0_ALLOWED_CLIENT_IDS||!env.AUTH0_AUDIENCE)throw new Failure('service_not_configured',503);
 const raw=request.headers.get('Authorization')||'';if(!raw.startsWith('Bearer '))throw new Failure('unauthorized',401);
 try{const issuer=new URL(env.AUTH0_ISSUER);if(issuer.protocol!=='https:')throw Error();const uri=new URL('.well-known/jwks.json',issuer).href;if(!keysets.has(uri))keysets.set(uri,createRemoteJWKSet(new URL(uri)));return await verifyPrincipal(raw.slice(7),env,keysets.get(uri))}catch{throw new Failure('unauthorized',401)}
}

export async function verifyPrincipal(raw,env,keyset){const {payload}=await jwtVerify(raw,keyset,{issuer:env.AUTH0_ISSUER,audience:env.AUTH0_AUDIENCE,algorithms:['RS256'],requiredClaims:['exp','iat','sub','iss','aud']});if(!env.AUTH0_ALLOWED_CLIENT_IDS.split(',').includes(payload.azp)||!payload.scope?.split(' ').includes('macbridge:control'))throw Error();return {user_id:payload.sub,client_id:payload.azp}}

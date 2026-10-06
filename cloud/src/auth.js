import {createRemoteJWKSet,jwtVerify} from 'jose';
import {Failure} from './common.js';
const firebaseKeys=createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
export async function authenticate(request,env){
 if(!env.FIREBASE_PROJECT_ID)throw new Failure('service_not_configured',503);
 const raw=request.headers.get('Authorization')||'';
 if(!raw.startsWith('Bearer '))throw new Failure('unauthorized',401);
 try{return await verifyPrincipal(raw.slice(7),env,firebaseKeys)}catch(e){throw e instanceof Failure?e:new Failure('unauthorized',401)}
}
// Password accounts are public but must prove their email before they can use any account endpoint.
const providers=env=>['google.com','facebook.com',...(env.PASSWORD_ENABLED==='true'?['password']:[])];
export async function verifyPrincipal(raw,env,keyset){
 const project=env.FIREBASE_PROJECT_ID;
 const {payload}=await jwtVerify(raw,keyset,{issuer:`https://securetoken.google.com/${project}`,audience:project,algorithms:['RS256'],requiredClaims:['exp','iat','auth_time','sub','iss','aud']});
 const now=Math.floor(Date.now()/1000);
 if(typeof payload.sub!=='string'||!payload.sub.length||payload.sub.length>128||typeof payload.iat!=='number'||payload.iat>now+5||typeof payload.auth_time!=='number'||payload.auth_time>now+5||!providers(env).includes(payload.firebase?.sign_in_provider)||(payload.firebase?.sign_in_provider==='google.com'&&payload.email_verified!==true))throw Error('Invalid Firebase identity');
 if(payload.firebase.sign_in_provider==='password'&&payload.email_verified!==true)throw new Failure('email_not_verified',403);
 return {user_id:payload.sub,client_id:'wand-dashboard',auth_time:payload.auth_time};
}

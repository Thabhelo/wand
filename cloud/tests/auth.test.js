import {it,expect} from 'vitest';
import {generateKeyPair,SignJWT} from 'jose';
import {verifyPrincipal,authenticate} from '../src/auth.js';
import relay from '../src/index.js';
const settings={FIREBASE_PROJECT_ID:'wand-test'};
it('verifies Firebase signature, project, times, user and Google identity',async()=>{
 const {privateKey,publicKey}=await generateKeyPair('RS256');
 const make=claims=>new SignJWT({sub:'alice',email_verified:true,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'google.com'},...claims}).setProtectedHeader({alg:'RS256'}).setIssuedAt().setIssuer(claims.iss||'https://securetoken.google.com/wand-test').setAudience(claims.aud||'wand-test').setExpirationTime(claims.exp||'5m').sign(privateKey);
 expect((await verifyPrincipal(await make({}),settings,publicKey)).user_id).toBe('alice');
 expect((await verifyPrincipal(await make({firebase:{sign_in_provider:'facebook.com'},email_verified:false}),settings,publicKey)).user_id).toBe('alice');
 for(const claims of [{email_verified:false},{firebase:{sign_in_provider:'anonymous'}},{sub:''},{auth_time:9999999999},{iss:'https://attacker.invalid/'},{aud:'other'},{exp:1}])await expect(verifyPrincipal(await make(claims),settings,publicKey)).rejects.toBeDefined();
 const other=await generateKeyPair('RS256');await expect(verifyPrincipal(await make({}),settings,other.publicKey)).rejects.toBeDefined();
});
it('fails closed without Firebase configuration',async()=>{await expect(authenticate(new Request('https://api.example/v1/devices',{headers:{Authorization:'Bearer anything'}}),{})).rejects.toMatchObject({code:'service_not_configured'})});
it('accepts password sign-in only when enabled and only with a verified email',async()=>{
 const {privateKey,publicKey}=await generateKeyPair('RS256');
 const make=claims=>new SignJWT({sub:'pat',email:'pat@example.com',email_verified:true,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'password'},...claims}).setProtectedHeader({alg:'RS256'}).setIssuedAt().setIssuer('https://securetoken.google.com/wand-test').setAudience(claims.aud||'wand-test').setExpirationTime('5m').sign(privateKey);
 const on={...settings,PASSWORD_ENABLED:'true'};
 expect(await verifyPrincipal(await make({}),on,publicKey)).toMatchObject({user_id:'pat',client_id:'wand-dashboard'});
 // Identity is the Firebase UID: two verified accounts never share one because their emails match.
 expect((await verifyPrincipal(await make({sub:'someone-else'}),on,publicKey)).user_id).toBe('someone-else');
 for(const claims of [{email_verified:false},{email_verified:undefined},{email_verified:'true'}])await expect(verifyPrincipal(await make(claims),on,publicKey)).rejects.toMatchObject({code:'email_not_verified',status:403});
 for(const env of [settings,{...settings,PASSWORD_ENABLED:'false'},{...settings,PASSWORD_ENABLED:'TRUE'}])await expect(verifyPrincipal(await make({}),env,publicKey)).rejects.toBeDefined();
 // Enabling passwords never loosens Google's verified-email rule or admits other providers.
 await expect(verifyPrincipal(await make({firebase:{sign_in_provider:'google.com'},email_verified:false}),on,publicKey)).rejects.toBeDefined();
 await expect(verifyPrincipal(await make({firebase:{sign_in_provider:'anonymous'}}),on,publicKey)).rejects.toBeDefined();
 await expect(verifyPrincipal(await make({aud:'other'}),on,publicKey)).rejects.toBeDefined();
});
it('offers email sign-in in public config only when enabled',async()=>{
 const config=async env=>(await relay.fetch(new Request('https://api.getwand.app/config'),{FACEBOOK_ENABLED:'false',...env})).json();
 expect((await config({})).passwordEnabled).toBe(false);expect((await config({PASSWORD_ENABLED:'true'})).passwordEnabled).toBe(true);
});

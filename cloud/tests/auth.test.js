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
it('accepts password sign-in only for a designated reviewer UID with a verified email',async()=>{
 const {privateKey,publicKey}=await generateKeyPair('RS256');
 const make=claims=>new SignJWT({sub:'reviewer-uid',email:'reviewer@example.com',email_verified:true,auth_time:Math.floor(Date.now()/1000),firebase:{sign_in_provider:'password'},...claims}).setProtectedHeader({alg:'RS256'}).setIssuedAt().setIssuer('https://securetoken.google.com/wand-test').setAudience('wand-test').setExpirationTime('5m').sign(privateKey);
 const allowed={...settings,REVIEWER_UIDS:'someone-else,reviewer-uid'};
 expect(await verifyPrincipal(await make({}),allowed,publicKey)).toMatchObject({user_id:'reviewer-uid',client_id:'wand-dashboard'});
 // Same email on another UID, an unverified reviewer, a UID prefix and an empty or missing list are all rejected.
 for(const claims of [{sub:'intruder-uid'},{email_verified:false},{email_verified:undefined},{sub:'reviewer'},{sub:'reviewer-uid,'}])await expect(verifyPrincipal(await make(claims),allowed,publicKey)).rejects.toBeDefined();
 for(const env of [settings,{...settings,REVIEWER_UIDS:''},{...settings,REVIEWER_UIDS:','}])await expect(verifyPrincipal(await make({}),env,publicKey)).rejects.toBeDefined();
 // The reviewer list never loosens Google's verified-email rule or admits other providers.
 await expect(verifyPrincipal(await make({firebase:{sign_in_provider:'google.com'},email_verified:false}),allowed,publicKey)).rejects.toBeDefined();
 await expect(verifyPrincipal(await make({firebase:{sign_in_provider:'anonymous'}}),allowed,publicKey)).rejects.toBeDefined();
});
it('offers reviewer sign-in in public config only when a reviewer is designated',async()=>{
 const config=async env=>(await relay.fetch(new Request('https://api.getwand.app/config'),{FACEBOOK_ENABLED:'false',...env})).json();
 expect((await config({})).passwordEnabled).toBe(false);expect((await config({REVIEWER_UIDS:','})).passwordEnabled).toBe(false);
 const shown=await config({REVIEWER_UIDS:'reviewer-uid'});expect(shown.passwordEnabled).toBe(true);expect(JSON.stringify(shown)).not.toContain('reviewer-uid');
});

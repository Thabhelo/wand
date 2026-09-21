import {it,expect} from 'vitest';
import {generateKeyPair,SignJWT} from 'jose';
import {verifyPrincipal,authenticate} from '../src/auth.js';
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

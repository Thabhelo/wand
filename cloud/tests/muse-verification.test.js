import {expect,it} from 'vitest';
import {museVerification} from '../src/muse-verification.js';
const challenge='a'.repeat(64), now=Date.parse('2026-11-09T08:00:00Z');
const env={MUSE_VERIFICATION_CHALLENGE:challenge,MUSE_VERIFICATION_EXPIRES:'2026-11-10T07:57:00Z'};
const request=(path=challenge,method='GET')=>new Request('https://api.getwand.app/.well-known/muse-challenge/'+path,{method});
it('serves only the active exact challenge as public plain text',async()=>{
 const response=museVerification(request(),env,now);
 expect(response.status).toBe(200);
 expect(await response.text()).toBe('muse-challenge='+challenge);
 expect(response.headers.get('Content-Type')).toBe('text/plain; charset=utf-8');
 expect(response.headers.get('Cache-Control')).toBe('no-store');
 expect(response.headers.has('Location')).toBe(false);
});
it('rejects expired, absent, malformed and mismatched proofs without reflecting input',async()=>{
 for(const config of [{},{...env,MUSE_VERIFICATION_CHALLENGE:'<script>'},{...env,MUSE_VERIFICATION_EXPIRES:'bad'},env]){
  const response=museVerification(request(),config,Date.parse(env.MUSE_VERIFICATION_EXPIRES));
  expect(response.status).toBe(404);expect(await response.text()).toBe('Not found');
 }
 expect(museVerification(request('b'.repeat(64)),env,now).status).toBe(404);
 expect(museVerification(request(challenge,'POST'),env,now).status).toBe(404);
 expect(museVerification(new Request('https://api.getwand.app/connector/v1/devices'),env,now)).toBe(null);
});

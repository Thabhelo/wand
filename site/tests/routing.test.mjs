import test from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
const env={RELAY_ORIGIN:'',ASSETS:{fetch:async request=>new Response(new URL(request.url).pathname)}};
test('dashboard root serves the pairing UI without a redirect',async()=>{const r=await worker.fetch(new Request('https://app.getwand.app/'),env);assert.equal(r.status,200);assert.equal(await r.text(),'/dashboard');assert.equal(r.headers.get('cache-control'),'no-store')});
test('unconfigured account service fails explicitly',async()=>{const r=await worker.fetch(new Request('https://app.getwand.app/config'),env);assert.equal(r.status,503);assert.equal((await r.json()).error.code,'service_not_configured')});
test('unconfigured commands cannot report success',async()=>{const r=await worker.fetch(new Request('https://app.getwand.app/v1/commands',{method:'POST',body:'{}'}),env);assert.equal(r.status,503)});
test('relay cannot be redirected to arbitrary credential recipients',async()=>{const r=await worker.fetch(new Request('https://app.getwand.app/config'),{...env,RELAY_ORIGIN:'https://other.example'});assert.equal(r.status,503)});
test('connect and www routes use the owned domains',async()=>{const r=await worker.fetch(new Request('https://getwand.app/connect'),env);assert.equal(r.headers.get('location'),'https://app.getwand.app/');const w=await worker.fetch(new Request('https://www.getwand.app/download'),env);assert.equal(w.headers.get('location'),'https://getwand.app/download')});
test('static pages block framing and referrer leaks',async()=>{const r=await worker.fetch(new Request('https://getwand.app/'),env);assert.equal(r.headers.get('x-frame-options'),'DENY');assert.equal(r.headers.get('referrer-policy'),'no-referrer')});
test('review socket rejects bad IDs and foreign origins before forwarding',async()=>{
 const configured={...env,RELAY_ORIGIN:'https://api.getwand.app'};
 let r=await worker.fetch(new Request('https://app.getwand.app/review-device?device_id=bad',{headers:{Upgrade:'websocket',Origin:'https://app.getwand.app'}}),configured);assert.equal(r.status,400);
 r=await worker.fetch(new Request('https://app.getwand.app/review-device?device_id=11111111-1111-4111-8111-111111111111',{headers:{Upgrade:'websocket',Origin:'https://evil.example'}}),configured);assert.equal(r.status,403);
});
test('account screens stay out of search without blocking public pages',async()=>{
 for(const url of ['https://app.getwand.app/','https://getwand.app/dashboard/','https://getwand.app/review/']) {
  const r=await worker.fetch(new Request(url),env);
  assert.equal(r.status,200);assert.equal(r.headers.get('x-robots-tag'),'noindex');
 }
 const r=await worker.fetch(new Request('https://getwand.app/privacy/'),env);
 assert.equal(r.headers.get('x-robots-tag'),null);
});

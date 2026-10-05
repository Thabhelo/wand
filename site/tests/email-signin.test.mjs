import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
const read=f=>fs.readFileSync(new URL('../../web/'+f,import.meta.url),'utf8');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
// user: null for signed out, otherwise the Firebase user the page restores.
async function setup({config={passwordEnabled:true},user=null,methods={}}={}){
 const dom=new JSDOM(read('index.html'),{url:'https://app.getwand.app',runScripts:'outside-only'}),w=dom.window,calls=[],requests=[];
 const record=name=>async(...args)=>{calls.push([name,...args]);return methods[name]?.(...args)};
 w.wandAuth={create:async()=>({isAuthenticated:async()=>!!user,getUser:async()=>user,getTokenSilently:async()=>'fake',loginWithRedirect:async()=>{},logout:async()=>{},...Object.fromEntries(['loginWithPassword','signUpWithPassword','resetPassword','sendVerification','refreshUser','linkPassword','linkGoogle'].map(n=>[n,record(n)]))})};
 w.fetch=async url=>{requests.push(url);const data=url==='/config'?{firebase:{apiKey:'fake',projectId:'fake'},...config}:[];return {ok:true,json:async()=>data}};
 for(const f of ['control-feedback.js','app-picker.js','capability-policy.js','dashboard.js'])w.eval(read(f));
 await wait(250);return {dom,w,calls,requests,$:s=>w.document.querySelector(s)};
}
const fill=($,email,password)=>{$('#email-toggle').click();$('#email-address').value=email;$('#email-password').value=password};
test('email sign-in stays hidden when the relay has it switched off',async()=>{
 const {dom,$}=await setup({config:{}});try{assert.equal($('#email-toggle').hidden,true);assert.equal($('#email-form').hidden,true);assert.equal($('#login').textContent,'Continue with Google');assert.equal($('#login').disabled,false)}finally{dom.window.close()}
});
test('signing in sends the typed credentials once and clears the password',async()=>{
 const {dom,calls,$}=await setup();try{
  assert.equal($('#email-toggle').hidden,false);assert.equal($('#email-form').hidden,true);
  fill($,' pat@example.com ','correct horse battery');$('#email-signin').click();await wait(50);
  assert.deepEqual(calls,[['loginWithPassword','pat@example.com','correct horse battery']]);assert.equal($('#email-password').value,'');assert.equal($('#email-error').textContent,'');
 }finally{dom.window.close()}
});
test('a rejected sign-in does not reveal which part was wrong',async()=>{
 const failed=Object.assign(Error('Firebase: Error (auth/invalid-credential).'),{code:'auth/invalid-credential'});
 const {dom,$}=await setup({methods:{loginWithPassword:async()=>{throw failed}}});try{
  fill($,'pat@example.com','wrong');$('#email-signin').click();await wait(50);
  assert.equal($('#email-error').textContent,'That email or password is not right. Check them and try again.');assert.equal($('#email-signin').disabled,false);
 }finally{dom.window.close()}
});
test('creating an account needs a 10-character password and then signs up once',async()=>{
 const {dom,calls,$}=await setup();try{
  fill($,'pat@example.com','short');$('#email-signup').click();await wait(50);
  assert.deepEqual(calls,[]);assert.match($('#email-error').textContent,/at least 10 characters/);
  $('#email-address').value='pat@example.com';$('#email-password').value='long enough password';$('#email-signup').click();await wait(50);
  assert.deepEqual(calls,[['signUpWithPassword','pat@example.com','long enough password']]);
 }finally{dom.window.close()}
});
test('an existing email is told to use its original sign-in, never merged',async()=>{
 const failed=Object.assign(Error('x'),{code:'auth/email-already-in-use'});
 const {dom,$}=await setup({methods:{signUpWithPassword:async()=>{throw failed}}});try{
  fill($,'pat@example.com','long enough password');$('#email-signup').click();await wait(50);
  assert.match($('#email-error').textContent,/already has a Wand account/);
 }finally{dom.window.close()}
});
test('password reset gives the same answer whether or not the account exists',async()=>{
 const missing=Object.assign(Error('x'),{code:'auth/user-not-found'});
 for(const methods of [{},{resetPassword:async()=>{throw missing}}]){
  const {dom,calls,$}=await setup({methods});try{
   $('#email-toggle').click();$('#email-reset').click();await wait(30);assert.match($('#email-error').textContent,/Enter your email above/);assert.deepEqual(calls,[]);
   $('#email-address').value='pat@example.com';$('#email-reset').click();await wait(50);
   assert.deepEqual(calls,[['resetPassword','pat@example.com']]);assert.equal($('#email-error').textContent,'If that email has a Wand password, a reset link is on its way.');
  }finally{dom.window.close()}
 }
});
const unverified={uid:'pat',email:'pat@example.com',emailVerified:false,providerData:[{providerId:'password'}]};
test('an unconfirmed password account sees only the confirmation screen and reaches no account data',async()=>{
 const {dom,calls,requests,$}=await setup({user:unverified,methods:{refreshUser:async()=>unverified}});try{
  assert.equal($('#verify-panel').hidden,false);assert.equal($('#workspace').hidden,true);assert.equal($('#welcome').hidden,true);assert.equal($('#logout').hidden,false);
  assert.match($('#verify-detail').textContent,/pat@example\.com/);assert.deepEqual(requests.filter(u=>u.startsWith('/v1/')),[]);
  $('#verify-resend').click();await wait(50);assert.ok(calls.some(c=>c[0]==='sendVerification'));assert.match($('#verify-status').textContent,/Sent/);
  $('#verify-check').click();await wait(50);assert.match($('#verify-status').textContent,/Not confirmed yet/);assert.equal($('#workspace').hidden,true);
 }finally{dom.window.close()}
});
test('confirming the email opens the dashboard without signing in again',async()=>{
 let state=unverified;
 const {dom,requests,$}=await setup({user:unverified,methods:{refreshUser:async()=>state}});try{
  assert.equal($('#verify-panel').hidden,false);state={...unverified,emailVerified:true};
  $('#verify-check').click();await wait(300);
  assert.equal($('#verify-panel').hidden,true);assert.equal($('#workspace').hidden,false);assert.ok(requests.includes('/v1/devices'));
 }finally{dom.window.close()}
});
test('account settings offer only the sign-in method the account lacks',async()=>{
 const google={uid:'g',email:'g@example.com',emailVerified:true,providerData:[{providerId:'google.com'}]};
 const password={uid:'p',email:'p@example.com',emailVerified:true,providerData:[{providerId:'password'}]};
 let page=await setup({user:google});try{
  assert.equal(page.$('#password-link-section').hidden,false);assert.equal(page.$('#google-link-section').hidden,true);
  page.$('#password-link-input').value='short';page.$('#password-link-form').dispatchEvent(new page.w.Event('submit',{cancelable:true}));await wait(50);assert.deepEqual(page.calls,[]);
  page.$('#password-link-input').value='long enough password';page.$('#password-link-form').dispatchEvent(new page.w.Event('submit',{cancelable:true}));await wait(50);
  assert.deepEqual(page.calls,[['linkPassword','long enough password']]);assert.equal(page.$('#password-link-section').hidden,true);assert.equal(page.$('#password-link-input').value,'');
 }finally{page.dom.window.close()}
 page=await setup({user:password});try{
  assert.equal(page.$('#password-link-section').hidden,true);assert.equal(page.$('#google-link-section').hidden,false);
  page.$('#google-link').click();await wait(50);assert.deepEqual(page.calls,[['linkGoogle']]);assert.equal(page.$('#google-link-section').hidden,true);
 }finally{page.dom.window.close()}
 page=await setup({user:google,config:{}});try{assert.equal(page.$('#password-link-section').hidden,true)}finally{page.dom.window.close()}
});

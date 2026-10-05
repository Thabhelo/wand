import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
const read=f=>fs.readFileSync(new URL('../../web/'+f,import.meta.url),'utf8');
async function setup(config,login){
 const dom=new JSDOM(read('index.html'),{url:'https://app.getwand.app',runScripts:'outside-only'}),w=dom.window,calls=[];
 w.wandAuth={create:async()=>({isAuthenticated:async()=>false,loginWithRedirect:async()=>{},loginWithPassword:async(...args)=>{calls.push(args);if(login)await login()},logout:async()=>{}})};
 w.fetch=async url=>{if(url!=='/config')throw Error('Unexpected request '+url);return {ok:true,json:async()=>({firebase:{apiKey:'fake',projectId:'fake'},...config})}};
 for(const f of ['control-feedback.js','app-picker.js','capability-policy.js','dashboard.js'])w.eval(read(f));
 await new Promise(r=>setTimeout(r,200));return {dom,w,calls,$:s=>w.document.querySelector(s)};
}
const submit=async(w,$)=>{$('#reviewer-form').dispatchEvent(new w.Event('submit',{cancelable:true}));await new Promise(r=>setTimeout(r,50))};
test('reviewer sign-in stays hidden unless the relay designates a reviewer',async()=>{
 const {dom,$}=await setup({});try{assert.equal($('#reviewer-toggle').hidden,true);assert.equal($('#reviewer-form').hidden,true);assert.equal($('#login').textContent,'Continue with Google');assert.equal($('#login').disabled,false)}finally{dom.window.close()}
});
test('reviewer form sends the typed credentials once and never keeps the password',async()=>{
 const {dom,w,calls,$}=await setup({passwordEnabled:true});try{
  assert.equal($('#reviewer-toggle').hidden,false);assert.equal($('#reviewer-form').hidden,true);assert.equal($('#login').textContent,'Continue with Google');
  $('#reviewer-toggle').click();assert.equal($('#reviewer-form').hidden,false);
  $('#reviewer-email').value=' reviewer@example.com ';$('#reviewer-password').value='correct horse';await submit(w,$);
  assert.deepEqual(calls,[['reviewer@example.com','correct horse']]);assert.equal($('#reviewer-password').value,'');assert.equal($('#reviewer-error').textContent,'');
 }finally{dom.window.close()}
});
test('reviewer form explains a rejected sign-in without revealing which part was wrong',async()=>{
 const failed=Object.assign(Error('Firebase: Error (auth/invalid-credential).'),{code:'auth/invalid-credential'});
 const {dom,w,$}=await setup({passwordEnabled:true},async()=>{throw failed});try{
  $('#reviewer-toggle').click();$('#reviewer-email').value='someone@example.com';$('#reviewer-password').value='wrong';await submit(w,$);
  assert.equal($('#reviewer-error').textContent,'That email or password is not right. Check them and try again.');assert.equal($('#reviewer-password').value,'');assert.equal($('#reviewer-submit').disabled,false);
 }finally{dom.window.close()}
});

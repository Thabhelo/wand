import {test} from 'node:test';
import assert from 'node:assert/strict';
import {support} from '../src/support.js';
const body={email:'visitor@example.com',name:'Visitor',topic:'Connection',message:'My Mac appears offline.'};
const request=(data=body,headers={})=>new Request('https://getwand.app/api/support',{method:'POST',headers:{Origin:'https://getwand.app','Content-Type':'application/json',...headers},body:JSON.stringify(data)});
const environment=()=>({SUPPORT_RECIPIENT:'private@example.com',SUPPORT_LIMIT:{limit:async()=>({success:true})},SUPPORT_EMAIL:{send:async()=>({messageId:'test'})}});
test('delivers to server-configured recipient and sets visitor reply address',async()=>{const env=environment();let sent;env.SUPPORT_EMAIL.send=async value=>{sent=value;};const response=await support(request({...body,to:'attacker@example.com'}),env);assert.equal(response.status,200);assert.equal(sent.to,'private@example.com');assert.equal(sent.replyTo,body.email);assert.match(sent.text,/My Mac appears offline/);assert.ok(!(await response.text()).includes('private@example.com'));});
test('email failure never reports success or leaks provider details',async()=>{const env=environment();env.SUPPORT_EMAIL.send=async()=>{throw Error('private provider details');};const response=await support(request(),env);assert.equal(response.status,503);assert.ok(!(await response.text()).includes('private provider'));});
test('rejects cross-origin, invalid email, header injection, honeypot and oversized body',async()=>{assert.equal((await support(request(body,{Origin:'https://evil.example'}),environment())).status,403);for(const data of [{...body,email:'bad'},{...body,email:'a@example.com\r\nBcc:other@example.com'},{...body,website:'bot'},{...body,message:''}])assert.equal((await support(request(data),environment())).status,400);assert.equal((await support(request({...body,message:'x'.repeat(17000)}),environment())).status,413);});
test('rate limit blocks sending',async()=>{const env=environment();env.SUPPORT_LIMIT.limit=async()=>({success:false});env.SUPPORT_EMAIL.send=()=>assert.fail('must not send');const response=await support(request(),env);assert.equal(response.status,429);assert.equal(response.headers.get('Retry-After'),'60');});

import {JSDOM} from 'jsdom';
import {readFileSync} from 'node:fs';
test('form preserves a failed message, retries, then clears only after success',async()=>{
 const dom=new JSDOM(readFileSync(new URL('../public/support/index.html',import.meta.url),'utf8'),{runScripts:'outside-only',url:'https://getwand.app/support/'});
 const {window}=dom;let succeed=false,calls=0;
 window.fetch=async(_url,options)=>{calls++;assert.equal(JSON.parse(options.body).email,'visitor@example.com');return {ok:succeed,json:async()=>({message:succeed?'Message sent. We’ll reply to your email.':'Please try again shortly.'})};};
 window.eval(readFileSync(new URL('../public/support/support.js',import.meta.url),'utf8'));
 const form=window.document.querySelector('form');form.elements.email.value='visitor@example.com';form.elements.message.value='My Mac appears offline.';
 form.dispatchEvent(new window.Event('submit',{cancelable:true}));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(form.elements.message.value,'My Mac appears offline.');assert.match(window.document.querySelector('#send-status').textContent,/try again/);assert.equal(form.querySelector('button').disabled,false);
 succeed=true;form.dispatchEvent(new window.Event('submit',{cancelable:true}));await new Promise(resolve=>setImmediate(resolve));
 assert.equal(calls,2);assert.equal(form.elements.message.value,'');assert.match(window.document.querySelector('#send-status').textContent,/Message sent/);dom.window.close();
});

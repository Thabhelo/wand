import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {supportEmail} from '../src/email-template.js';
test('branded email has equivalent text, safe reply links and readable multiline content',()=>{
 const email='person+help@example.com';
 const message='First line\nSecond line & details';
 const result=supportEmail({name:'Alex',email,topic:'Connection',message});
 const dom=new JSDOM(result.html);const doc=dom.window.document;
 assert.match(doc.body.textContent,/New support message/);assert.match(result.text,/First line\nSecond line & details/);
 assert.equal(doc.querySelectorAll('br').length,1);
 const reply=[...doc.querySelectorAll('a')].find(a=>a.textContent==='Reply to Alex');
 assert.equal(decodeURIComponent(reply.getAttribute('href').split('?')[0]),`mailto:${email}`);
 assert.ok(!doc.querySelector('script,img,iframe'));dom.window.close();
});
test('visitor HTML cannot become markup or inject a link',()=>{
 const result=supportEmail({name:'<img src=x onerror=alert(1)>',email:'person@example.com',topic:'Account',message:'<script>alert(1)</script>\n<a href="https://evil.example">Click</a>'});
 const dom=new JSDOM(result.html);assert.equal(dom.window.document.querySelectorAll('script,img').length,0);
 assert.match(dom.window.document.body.textContent,/<script>alert\(1\)<\/script>/);
 assert.ok([...dom.window.document.querySelectorAll('a')].every(a=>!a.href.startsWith('https://evil.example')));dom.window.close();
});

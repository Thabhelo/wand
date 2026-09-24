import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';

const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');
async function setup(error,failedRequest=false,capabilities=null){
 const dom=new JSDOM(read('../public/desktop/index.html'),{url:'https://app.getwand.app/desktop/',runScripts:'outside-only'}),w=dom.window,commands=[];
 w.WandAppPicker=class{setDevice(){} value(){return {params:{bundle_id:'com.apple.TextEdit'},label:'TextEdit'}}};
 w.wandAuth={create:async()=>({isAuthenticated:async()=>true,getTokenSilently:async()=>'test-token'})};
 w.fetch=async url=>{
  let data={},ok=true;
  if(url==='/v1/devices')data=[{device_id:'mac',name:'Test Mac',online:true}];
  else if(url==='/v1/devices/mac/capabilities')data=capabilities||{contract_version:1,stale:false,actions:[{name:'desktop_observe',support:'supported',authorized:true,availability:'available'}]};
  else if(url==='/v1/commands'){commands.push(url);ok=!failedRequest;data=failedRequest?{error}:{command_id:'test'}}
  else if(url==='/v1/commands/test')data=error?{status:'failed',error}:{status:'succeeded',result:{snapshot_id:'test-view',elements:[],expires_at:new Date(Date.now()+30000).toISOString()}};
  return {ok,json:async()=>data};
 };
 for(const file of ['control-feedback.js','capability-policy.js'])w.eval(read('../../web/'+file));
 await w.eval('(async()=>{'+read('../public/desktop/desktop.js')+'})()');
 return {dom,w,commands};
}
test('Look at app reports the actual Accessibility denial in plain language',async()=>{
 const {dom,w}=await setup({code:'accessibility_permission_required',message:'accessibility_permission_required'});
 try{await w.document.querySelector('#observe').onclick();const text=w.document.querySelector('#status').textContent;assert.match(text,/macOS isn’t allowing Wand/);assert.match(text,/Privacy & Security → Accessibility/);assert.doesNotMatch(text,/desktop_observe|accessibility_permission_required/)}finally{dom.window.close()}
});
test('image permission denial names Screen Recording and leaves text-only observation usable',async()=>{
 const report={contract_version:1,stale:false,online:true,permissions:{desktop_control:'granted',accessibility:'granted',screen_recording:'denied'},actions:[{name:'desktop_observe',support:'supported',authorized:true,availability:'available',required_permissions:['desktop_control','accessibility']}],feature_status:{desktop_images:{support:'supported',authorized:true,availability:'blocked',reason:'permission_denied',required_permissions:['desktop_control','accessibility','screen_recording']}}};
 const {dom,w,commands}=await setup(null,false,report);
 try{
  w.document.querySelector('#capture').checked=true;
  await w.document.querySelector('#observe').onclick();
  const text=w.document.querySelector('#status').textContent;
  assert.match(text,/Screen Recording/);assert.match(text,/turn off images/);assert.doesNotMatch(text,/Accessibility/);assert.equal(commands.length,0);
  w.document.querySelector('#capture').checked=false;
  await w.document.querySelector('#observe').onclick();
  assert.equal(w.document.querySelector('#status').textContent,'App inspected.');assert.equal(commands.length,1);
 }finally{dom.window.close()}
});
test('text observation permission denial names Accessibility and prevents dispatch',async()=>{
 const report={contract_version:1,stale:false,online:true,permissions:{desktop_control:'granted',accessibility:'denied',screen_recording:'granted'},actions:[{name:'desktop_observe',support:'supported',authorized:true,availability:'blocked',reason:'permission_denied',required_permissions:['desktop_control','accessibility']}]};
 const {dom,w,commands}=await setup(null,false,report);
 try{await w.document.querySelector('#observe').onclick();const text=w.document.querySelector('#status').textContent;assert.match(text,/Accessibility/);assert.doesNotMatch(text,/Screen Recording/);assert.equal(commands.length,0)}finally{dom.window.close()}
});
test('desktop API and command failures hide unrecognized server details',async()=>{
 for(const failedRequest of [true,false]){
  const {dom,w}=await setup({code:'internal_new_error',message:'internal_new_error: private diagnostic details'},failedRequest);
  try{await w.document.querySelector('#observe').onclick();assert.equal(w.document.querySelector('#status').textContent,'Wand couldn’t confirm the result. Check your Mac before trying again.')}finally{dom.window.close()}
 }
});

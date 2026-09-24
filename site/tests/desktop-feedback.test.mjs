import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';

const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');
async function setup(error,failedRequest=false){
 const dom=new JSDOM(read('../public/desktop/index.html'),{url:'https://app.getwand.app/desktop/',runScripts:'outside-only'}),w=dom.window;
 w.WandAppPicker=class{setDevice(){} value(){return {params:{bundle_id:'com.apple.TextEdit'},label:'TextEdit'}}};
 w.wandAuth={create:async()=>({isAuthenticated:async()=>true,getTokenSilently:async()=>'test-token'})};
 w.fetch=async url=>{
  let data={},ok=true;
  if(url==='/v1/devices')data=[{device_id:'mac',name:'Test Mac',online:true}];
  else if(url==='/v1/devices/mac/capabilities')data={contract_version:1,stale:false,actions:[{name:'desktop_observe',support:'supported',authorized:true,availability:'available'}]};
  else if(url==='/v1/commands'){ok=!failedRequest;data=failedRequest?{error}:{command_id:'test'}}
  else if(url==='/v1/commands/test')data={status:'failed',error};
  return {ok,json:async()=>data};
 };
 for(const file of ['control-feedback.js','capability-policy.js'])w.eval(read('../../web/'+file));
 await w.eval('(async()=>{'+read('../public/desktop/desktop.js')+'})()');
 return {dom,w};
}
test('Look at app reports the actual Accessibility denial in plain language',async()=>{
 const {dom,w}=await setup({code:'accessibility_permission_required',message:'accessibility_permission_required'});
 try{await w.document.querySelector('#observe').onclick();const text=w.document.querySelector('#status').textContent;assert.match(text,/macOS isn’t allowing Wand/);assert.match(text,/Privacy & Security → Accessibility/);assert.doesNotMatch(text,/desktop_observe|accessibility_permission_required/)}finally{dom.window.close()}
});
test('desktop API and command failures hide unrecognized server details',async()=>{
 for(const failedRequest of [true,false]){
  const {dom,w}=await setup({code:'internal_new_error',message:'internal_new_error: private diagnostic details'},failedRequest);
  try{await w.document.querySelector('#observe').onclick();assert.equal(w.document.querySelector('#status').textContent,'Wand couldn’t confirm the result. Check your Mac before trying again.')}finally{dom.window.close()}
 }
});

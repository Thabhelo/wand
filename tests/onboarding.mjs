import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const script=fs.readFileSync(new URL('../web/dashboard.js',import.meta.url),'utf8');
const flush=async()=>{for(let i=0;i<20;i++)await new Promise(setImmediate)};
function harness({configured=true,signed=true,handoff='',initialDevices=[]}={}){
 const elements=new Map(),storage=new Map(),calls=[],timers=new Map();let nextTimer=0,deviceList=initialDevices,result={status:'succeeded',result:{}},failure=null;
 function element(){return {value:'',textContent:'',hidden:false,disabled:false,open:false,children:[],dataset:{},style:{},append(...items){this.children.push(...items)},replaceChildren(...items){this.children=items},setAttribute(k,v){this[k]=v},addEventListener(k,f){this['on'+k]=f},showModal(){this.open=true},close(){this.open=false},focus(){}}}
 const get=s=>{if(!elements.has(s))elements.set(s,element());return elements.get(s)};
 get('#confirm-input').hidden=true;get('#volume').value='50';
 const context={document:{hidden:false,querySelector:get,querySelectorAll:()=>[],createElement:element},location:{hash:handoff,pathname:'/',search:'',origin:'https://app.example'},history:{replaceState(){}},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},window:{addEventListener(){}},URL,URLSearchParams,AbortController,Date,Math,JSON,Error,String,Number,Object,console,clearTimeout:id=>timers.delete(id),setTimeout:(fn,ms)=>{const id=++nextTimer;timers.set(id,{fn,ms});return id},auth0:{createAuth0Client:async()=>({isAuthenticated:async()=>signed,getUser:async()=>({email:'reviewer@example.test'}),getTokenSilently:async()=>'test-token'})},fetch:async(url,options)=>{
  calls.push({url,body:options?.body?JSON.parse(options.body):null});let data,ok=true;
  if(url==='/config'){data=configured?{domain:'auth.example',clientId:'test-client',audience:'test-audience'}:{error:{code:'service_not_configured'}};ok=configured}
  else if(url==='/v1/devices')data=deviceList;
  else if(url==='/v1/pairing/preview')data={device_name:'My Mac',expires_at:'2099-01-01T00:00:00Z'};
  else if(url==='/v1/pairing/claim')data={device_id:'device',status:'claimed'};
  else if(url==='/v1/commands'){if(failure){data={error:failure};ok=false}else data={command_id:'command',status:'dispatched'}}
  else if(url==='/v1/commands/command')data=result;
  else throw Error('Unexpected '+url);
  return {ok,json:async()=>data};
 }};
 vm.createContext(context);vm.runInContext(script,context);
 return {get,storage,calls,timers,run:code=>vm.runInContext(code,context),setDevices:value=>deviceList=value,setResult:value=>result=value,setFailure:value=>failure=value};
}
const online={device_id:'device',name:'My Mac',online:true,last_seen:null};
{
 const h=harness({handoff:'#pair=ABC234'});await flush();assert.equal(h.get('#code').value,'ABC234');assert.equal(h.get('#account').textContent,'reviewer@example.test');assert.match(h.get('#pair-target').textContent,/My Mac/);assert(!h.calls.some(c=>c.url==='/v1/pairing/claim'));assert(h.get('#pair-dialog').open);
 await h.get('#claim').onsubmit({preventDefault(){}});await flush();assert.equal(h.calls.filter(c=>c.url==='/v1/pairing/claim').length,1);assert.match(h.get('#status').textContent,/Waiting for your Mac/);assert(!h.storage.has('wand-pair'));h.setDevices([online]);const timer=[...h.timers.values()].find(t=>t.ms>=3000&&t.ms<4000);await timer.fn();await flush();assert.match(h.get('#status').textContent,/connected to Wand/);
}
{
 const h=harness({configured:false});await flush();assert(h.get('#login').disabled);assert.match(h.get('#login-note').textContent,/not enabled/);assert(!h.calls.some(c=>c.url.startsWith('/v1/')));
}
{
 const h=harness({initialDevices:[online]});await flush();const pending=h.run("sendAction('quit_app',{app_name:'TextEdit'})");await flush();assert(h.get('#confirm-dialog').open);assert.match(h.get('#confirm-detail').textContent,/TextEdit.*My Mac/);assert(!h.calls.some(c=>c.url==='/v1/commands'));h.get('#confirm-cancel').onclick();await pending;assert(!h.calls.some(c=>c.url==='/v1/commands'));
 const approved=h.run("sendAction('run_shortcut',{name:'Focus'})");await flush();h.get('#confirm-form').onsubmit({preventDefault(){}});await approved;assert.equal(h.calls.filter(c=>c.url==='/v1/commands').length,1);assert.match(h.get('#status').textContent,/completed/);
}
{
 const h=harness({initialDevices:[{...online,online:false}]});await flush();await h.run("sendAction('mute')");assert(!h.calls.some(c=>c.url==='/v1/commands'));assert.match(h.get('#status').textContent,/offline/);
}
{
 const h=harness({initialDevices:[online]});await flush();h.setResult({status:'failed',error:{code:'action_not_allowlisted'}});const pending=h.run("sendAction('run_shortcut',{name:'Unknown'})");await flush();h.get('#confirm-form').onsubmit({preventDefault(){}});await pending;assert.match(h.get('#status').textContent,/allowed list/);assert(!h.get('#status').textContent.includes('completed'));
}
{
 const h=harness({initialDevices:[online]});await flush();h.setResult({status:'succeeded',result:{screen_locked:true}});await h.run("sendAction('get_state')");assert.match(h.get('#state-result').textContent,/locked/);assert.equal(h.get('#state-result').children.length,0);
 h.get('#url').value='javascript:alert(1)';h.get('#url-form').onsubmit({preventDefault(){}});assert.equal(h.calls.filter(c=>c.url==='/v1/commands').length,1);await h.run("sendAction('shell',{command:'whoami'})");assert.equal(h.calls.filter(c=>c.url==='/v1/commands').length,1);
}
{
 const h=harness({initialDevices:[online]});await flush();h.setResult({status:'delivered'});const pending=h.run("sendAction('mute')");await flush();assert(!h.get('#status').textContent.includes('completed'));h.setResult({status:'succeeded',result:{}});const timer=[...h.timers.values()].find(t=>t.ms===800);timer.fn();await pending;assert.match(h.get('#status').textContent,/completed/);
}
{
 const h=harness({initialDevices:[online]});await flush();h.setFailure({code:'device_offline',message:'offline',last_seen:'2026-09-20T12:00:00Z'});await h.run("sendAction('mute')");assert.match(h.get('#status').textContent,/offline/);assert.equal(h.get('#offline-notice').hidden,false);
}
console.log('Dashboard checks passed: pairing, absent configuration, confirmations and cancellation, offline fail-fast, rejected Shortcuts, locked privacy, URL/catalog validation, result polling.');

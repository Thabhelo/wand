import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';

const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');

async function setup({deferredClose=false}={}){
 const dom=new JSDOM(read('../public/review/index.html'),{url:'https://app.getwand.app/review/',runScripts:'outside-only'}),w=dom.window;
 const requests=[],sockets=[],intervals=new Map(),get=id=>w.document.getElementById(id);
 const setInterval=w.setInterval.bind(w),clearInterval=w.clearInterval.bind(w);
 w.setInterval=(fn,ms)=>{const id=setInterval(fn,ms);intervals.set(id,fn);return id};
 w.clearInterval=id=>{intervals.delete(id);clearInterval(id)};
 w.HTMLDialogElement.prototype.showModal=function(){this.open=true};
 w.HTMLDialogElement.prototype.close=function(){this.open=false;this.dispatchEvent(new w.Event('close'))};
 w.confirm=()=>{throw Error('The sandbox must not open a browser confirmation')};
 w.wandAuth={create:async()=>({isAuthenticated:async()=>true,getTokenSilently:async()=>'test-token'})};
 w.WebSocket=class{
  static OPEN=1;
  static autoReady=true;
  constructor(){this.readyState=1;this.sent=[];sockets.push(this);w.queueMicrotask(()=>this.onopen())}
  send(raw){const message=JSON.parse(raw);this.sent.push(message);if(message.type==='hello'&&w.WebSocket.autoReady)w.queueMicrotask(()=>this.receive({type:'ready'}))}
  receive(message){this.onmessage({data:JSON.stringify(message)})}
  finishClose(code=1000){this.readyState=3;this.onclose?.({code})}
  close(){this.readyState=3;if(!deferredClose)this.finishClose()}
 };
 w.fetch=async(path,options={})=>{
  const method=options.method||'GET',body=options.body?JSON.parse(options.body):null;
  requests.push({path,method,body});
  let value={};
  if(path==='/v1/pairing/code')value={device_id:'test-mac',code:'ABC234',bootstrap_token:'test-bootstrap'};
  else if(path==='/v1/commands')value={command_id:'test-command'};
  else if(path==='/v1/commands/test-command'){
   const command=requests.findLast(r=>r.path==='/v1/commands').body;
   value=command.params.name==='Not approved'?{status:'failed',error:{code:'action_not_allowlisted'}}:{status:'succeeded',result:{}};
  }
  return {ok:true,json:async()=>value};
 };
 await w.eval('(async()=>{'+read('../public/review/review.js')+'})()');
 await get('create').onclick();
 return {dom,w,get,requests,sockets,intervals,commands:()=>requests.filter(r=>r.path==='/v1/commands')};
}

test('simulated lock and both Shortcut tests require an accessible in-page confirmation',async()=>{
 for(const [selection,title,action,params] of [
  ['lock_screen','Lock the simulated Mac?','lock_screen',{}],
  ['run_shortcut','Run the test Shortcut?','run_shortcut',{name:'Review Demo'}],
  ['reject','Try an unapproved Shortcut?','run_shortcut',{name:'Not approved'}]
 ]){
  const {dom,w,get,commands}=await setup();
  try{
   get('action').value=selection;get('run').focus();const pending=get('run').onclick();
   const dialog=get('confirm-dialog');
   assert.equal(dialog.open,true);
   assert.equal(dialog.getAttribute('aria-labelledby'),'confirm-title');
   assert.equal(dialog.getAttribute('aria-describedby'),'confirm-detail');
   assert.equal(get('confirm-title').textContent,title);
   assert.match(get('confirm-detail').textContent,/real Mac/);
   assert.equal(w.document.activeElement,get('confirm-cancel'));
   assert.equal(commands().length,0);
   get('confirm-accept').click();await pending;
   assert.equal(dialog.open,false);assert.equal(commands().length,1);
   assert.deepEqual(commands()[0].body,{device_id:'test-mac',action,params});
   assert.equal(get('run').disabled,false);assert.equal(w.document.activeElement,get('run'));
   if(selection==='reject')assert.match(get('output').textContent,/action_not_allowlisted/);
  }finally{dom.window.close()}
 }
});

test('Cancel, Escape and closing the dialog cancel without sending a command and restore focus',async()=>{
 for(const cancel of ['button','escape','close']){
  const {dom,w,get,commands}=await setup();
  try{
   get('action').value='lock_screen';get('run').focus();const pending=get('run').onclick();
   if(cancel==='button')get('confirm-cancel').click();
   else if(cancel==='escape'){
    const event=new w.Event('cancel',{cancelable:true});get('confirm-dialog').dispatchEvent(event);assert.equal(event.defaultPrevented,true);
   }else get('confirm-dialog').close();
   await pending;
   assert.equal(commands().length,0);assert.equal(get('confirm-dialog').open,false);
   assert.equal(get('run').disabled,false);assert.equal(w.document.activeElement,get('run'));
  }finally{dom.window.close()}
 }
});

test('revocation requires confirmation and returns focus to Create test Mac after removing controls',async()=>{
 const {dom,w,get,requests}=await setup();
 try{
  get('revoke').focus();let pending=get('revoke').onclick();
  assert.equal(get('confirm-title').textContent,'Revoke this test Mac?');
  assert.match(get('confirm-detail').textContent,/real Macs are unaffected/);
  assert.equal(requests.filter(r=>r.method==='DELETE').length,0);
  get('confirm-cancel').click();await pending;
  assert.equal(requests.filter(r=>r.method==='DELETE').length,0);
  assert.equal(get('controls').hidden,false);assert.equal(w.document.activeElement,get('revoke'));
  pending=get('revoke').onclick();get('confirm-accept').click();await pending;
  assert.deepEqual(requests.filter(r=>r.method==='DELETE').map(r=>r.path),['/v1/devices/test-mac']);
  assert.equal(get('controls').hidden,true);assert.equal(w.document.activeElement,get('create'));
  assert.match(get('output').textContent,/old device credential no longer works/);
 }finally{dom.window.close()}
});

test('read-only status runs without a confirmation',async()=>{
 const {dom,get,commands}=await setup();
 try{
  await get('run').onclick();
  assert.equal(get('confirm-dialog').open,false);
  assert.equal(commands().length,1);assert.equal(commands()[0].body.action,'get_state');
 }finally{dom.window.close()}
});

test('late events from an old socket cannot interrupt the reconnected test Mac',async()=>{
 const {dom,get,sockets,intervals}=await setup({deferredClose:true});
 try{
  const old=sockets[0];await get('offline').onclick();await get('online').onclick();
  const current=sockets[1];assert.equal(intervals.size,1);
  old.finishClose(1000);old.onerror();old.receive({type:'ready'});
  old.receive({type:'revoke'});
  old.receive({type:'command',command_id:'old-command',action:'lock_screen',params:{},expires_at:new Date(Date.now()+15000).toISOString()});
  assert.equal(get('status').textContent,'Simulated Mac online');
  assert.equal(get('controls').hidden,false);assert.equal(current.readyState,1);assert.equal(intervals.size,1);
  assert.equal(current.sent.filter(m=>m.type==='result').length,0);
  for(const heartbeat of intervals.values())heartbeat();
  assert.equal(current.sent.at(-1).type,'heartbeat');
  assert.equal(current.sent.at(-1).capabilities.screen_state,'unlocked');
 }finally{dom.window.close()}
});

test('repeated lock stays online, returns an idempotent result and preserves locked privacy after reconnect',async()=>{
 const {dom,get,sockets,intervals}=await setup();
 try{
  const expiry=()=>new Date(Date.now()+15000).toISOString();
  sockets[0].receive({type:'command',command_id:'lock-1',action:'lock_screen',params:{},expires_at:expiry()});
  await get('offline').onclick();await get('online').onclick();
  const current=sockets[1];
  current.receive({type:'command',command_id:'lock-2',action:'lock_screen',params:{},expires_at:expiry()});
  current.receive({type:'command',command_id:'status',action:'get_state',params:{},expires_at:expiry()});
  current.receive({type:'ready'});
  assert.deepEqual(sockets[0].sent.find(m=>m.type==='result').data,{already_locked:false});
  assert.deepEqual(current.sent.find(m=>m.command_id==='lock-2'&&m.type==='result').data,{already_locked:true});
  assert.deepEqual(current.sent.find(m=>m.command_id==='status'&&m.type==='result').data,{screen_locked:true});
  assert.equal(get('status').textContent,'Simulated Mac online');assert.equal(intervals.size,1);
 }finally{dom.window.close()}
});

test('socket close before ready settles the connection attempt and leaves Reconnect usable',async()=>{
 const {dom,w,get,sockets}=await setup();
 try{
  await get('offline').onclick();w.WebSocket.autoReady=false;
  const pending=get('online').onclick();await Promise.resolve();
  sockets[1].finishClose(4000);await pending;
  assert.equal(get('online').disabled,false);
  assert.match(get('status').textContent,/heartbeat timed out/);
  assert.match(get('output').textContent,/heartbeat timed out/);
 }finally{dom.window.close()}
});

test('token revocation wipes simulated connection state and keeps a clear status',async()=>{
 for(const event of ['message','close']){
  const {dom,get,sockets,intervals}=await setup({deferredClose:true});
  try{
   if(event==='message')sockets[0].receive({type:'revoke'});else sockets[0].finishClose(4003);
   sockets[0].finishClose(4003);
   assert.equal(get('controls').hidden,true);assert.match(get('status').textContent,/revoked/);assert.equal(intervals.size,0);
   await get('create').onclick();assert.equal(sockets.length,2);assert.equal(get('status').textContent,'Simulated Mac online');
  }finally{dom.window.close()}
 }
});

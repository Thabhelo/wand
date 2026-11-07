// Runs the dashboard in a vm with a stub DOM, fake clock and manual timers: node --test web/tests/*.test.mjs
import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const read=f=>fs.readFileSync(new URL('../'+f,import.meta.url),'utf8');
const scripts=['control-feedback.js','capability-policy.js','dashboard.js'].map(read);
const flush=async()=>{for(let i=0;i<30;i++)await new Promise(setImmediate)};
const local=(y,m,d,h,min)=>new Date(y,m-1,d,h,min).getTime();
function harness({devices=[],history=null,capabilities=null,now=local(2026,11,7,9,0)}={}){
 let clock=now;const elements=new Map(),storage=new Map(),calls=[],commands=[],timers=new Map(),perAction=new Map();let nextTimer=0,result={status:'succeeded',result:{}};
 class FakeDate extends Date{constructor(...a){super(...(a.length?a:[clock]))} static now(){return clock}}
 function element(){return {value:'',textContent:'',hidden:false,disabled:false,open:false,children:[],dataset:{},style:{},className:'',append(...items){this.children.push(...items)},replaceChildren(...items){this.children=items},setAttribute(k,v){this[k]=v},addEventListener(k,f){this['on'+k]=f},closest(){return null},showModal(){this.open=true},close(){this.open=false},focus(){}}}
 const get=s=>{if(!elements.has(s))elements.set(s,element());return elements.get(s)};
 get('#confirm-input').hidden=true;get('#volume').value='50';
 if(history)storage.set('wand-history-tester',JSON.stringify(history));
 const report=capabilities||{contract_version:1,revision:1,source:'device',stale:false,online:true,actions:['get_state','mute','unmute','open_app','set_volume'].map(name=>({name,support:'supported',authorized:true,availability:'available',reason:null}))};
 const context={WandAppPicker:class{constructor(root,options){this.load=options.load} setDevice(){} value(){return {params:{},label:''}}},document:{hidden:false,addEventListener(){},querySelector:get,querySelectorAll:()=>[],createElement:element},location:{hash:'',pathname:'/',search:'',origin:'https://app.example'},history:{replaceState(){}},sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v),removeItem:k=>storage.delete(k)},window:{addEventListener(){},wandAuth:{create:async()=>({isAuthenticated:async()=>true,getUser:async()=>({uid:'tester',email:'tester@example.test'}),getTokenSilently:async()=>'token'})}},URL,URLSearchParams,AbortController,Date:FakeDate,Math,JSON,Error,String,Number,Object,Array,Map,Boolean,Promise,console,clearTimeout:id=>timers.delete(id),setTimeout:(fn,ms)=>{const id=++nextTimer;timers.set(id,{fn,ms});return id},fetch:async(url,options)=>{
  calls.push(url);let data;
  if(url==='/config')data={firebase:{apiKey:'test',projectId:'wand-test'}};
  else if(url==='/v1/devices')data=devices;
  else if(url==='/v1/devices/mac/capabilities')data=report;
  else if(url==='/v1/connections')data=[];
  else if(url==='/v1/commands'){commands.push(JSON.parse(options.body).action);data={command_id:'command',status:'dispatched'}}
  else if(url==='/v1/commands/command')data=perAction.get(commands.at(-1))??result;
  else throw Error('Unexpected '+url);
  return {ok:true,json:async()=>data};
 }};
 vm.createContext(context);vm.runInContext(scripts[0],context);vm.runInContext(scripts[1],context);
 // The policy and feedback scripts attach to window; dashboard.js reads them as globals.
 Object.assign(context,{WandCapabilities:context.window.WandCapabilities,WandFeedback:context.window.WandFeedback});vm.runInContext(scripts[2],context);
 return {get,calls,commands,timers,storage,rows:()=>get('#activity').children,run:code=>vm.runInContext(code,context),setDevices:v=>{devices=v},setResult:v=>{result=v},setResultFor:(action,v)=>{if(v===undefined)perAction.delete(action);else perAction.set(action,v)},has:ms=>[...timers.values()].some(t=>t.ms===ms),advance:ms=>{clock+=ms},fire:ms=>{const entry=[...timers.entries()].find(([,t])=>t.ms===ms);if(!entry)throw Error('No '+ms+'ms timer');timers.delete(entry[0]);return entry[1].fn()},count:url=>calls.filter(c=>c===url).length};
}
const mac=online=>({device_id:'mac',name:'My Mac',online,last_seen:null});
const rowText=li=>JSON.stringify(li.children.map(c=>[c.textContent,...(c.children||[]).map(x=>x.textContent)]));
const stale='Wand couldn’t confirm the result. Check your Mac before trying again.';

test('restored notes show their time and clear when the Mac comes back online',async()=>{
 const yesterday=new Date(local(2026,11,6,20,14)).toISOString(),today=new Date(local(2026,11,7,8,30)).toISOString();
 const h=harness({devices:[mac(false)],history:[{deviceId:'mac',action:'mute',label:'Mute',time:today,status:'failed',error:stale},{deviceId:'mac',action:'open_app',label:'Open app · Safari',time:yesterday,status:'failed',error:stale}]});
 await flush();
 const [first,second]=h.rows();assert.equal(h.rows().length,2);
 assert.match(first.children[0].children[1].textContent,/^at \d/);assert.match(second.children[0].children[1].textContent,/^yesterday \d/);
 assert.match(rowText(first),/couldn’t confirm/);assert.match(rowText(second),/couldn’t confirm/);
 h.setDevices([mac(true)]);await h.run('devices()');await flush();
 assert.equal(h.rows().length,2);assert.doesNotMatch(rowText(h.rows()[0]),/couldn’t confirm/);assert.doesNotMatch(rowText(h.rows()[1]),/couldn’t confirm/);
 assert.equal(h.rows()[1].children[1].textContent,'Failed');
 assert.ok(!JSON.parse(h.storage.get('wand-history-tester')).some(r=>r.error),'cleared notes stay cleared after reload');
});
test('a successful command clears restored notes for its own section only',async()=>{
 const time=new Date(local(2026,11,7,8,30)).toISOString();
 const h=harness({devices:[mac(true)],history:[{deviceId:'mac',action:'mute',label:'Mute',time,status:'failed',error:stale},{deviceId:'mac',action:'open_app',label:'Open app · Safari',time,status:'failed',error:stale}]});
 await flush();assert.equal(h.rows().length,2);assert.match(rowText(h.rows()[0]),/couldn’t confirm/);
 await h.run("sendAction('mute')");await flush();
 const rows=h.rows();assert.equal(rows.length,3);
 assert.match(rowText(rows[0]),/Mac muted/);assert.doesNotMatch(rowText(rows[1]),/couldn’t confirm/);assert.match(rowText(rows[2]),/couldn’t confirm/);
 assert.doesNotMatch(rows[0].children[0].children[1].textContent,/^at |^yesterday /,'live rows keep the plain clock');
});
test('a live command failure keeps the generic confirm note in the activity list',async()=>{
 const h=harness({devices:[mac(true)]});await flush();
 h.setResultFor('mute',{status:'failed',error:{code:'something_new'}});await h.run("sendAction('mute')");await flush();
 assert.match(rowText(h.rows()[0]),/couldn’t confirm/);assert.equal(h.get('#status').textContent,stale);assert.equal(h.rows()[0].children[1].textContent,'Failed');
 assert.doesNotMatch(h.get('#now-playing').textContent,/couldn’t confirm/,'a command failure never lands in the state reader');
 h.setResult({status:'succeeded',result:{}});await h.run("sendAction('unmute')");await flush();
 assert.match(rowText(h.rows()[1]),/couldn’t confirm/);
});
test('capabilities are reused for 30 seconds between presses and refetched afterwards',async()=>{
 const h=harness({devices:[mac(true)]});await flush();
 const url='/v1/devices/mac/capabilities',before=h.count(url);assert.equal(before,1);
 await h.run("sendAction('mute')");await h.run("sendAction('unmute')");await flush();
 assert.equal(h.count(url),before,'repeat presses skip the capabilities round trip');
 assert.match(h.get('#status').textContent,/unmuted/,'both presses were sent');
 h.advance(31000);await h.run("sendAction('mute')");await flush();assert.equal(h.count(url),before+1);
 assert.equal(h.run('capabilitiesFresh()'),true);
 h.run('capabilityOnline=false');assert.equal(h.run('capabilitiesFresh()'),false,'an online change invalidates the cache');
 h.run('capabilityOnline=true;capabilities=null');assert.equal(h.run('capabilitiesFresh()'),false,'a missing report is never fresh');
});
test('commands give up 15.5 seconds after dispatch with a 15 second message',async()=>{
 const h=harness({devices:[mac(true)]});await flush();
 h.setResult({status:'delivered'});const pending=h.run("sendAction('mute')");await flush();
 let polls=0;while(h.timers.size&&[...h.timers.values()].some(t=>t.ms===800)){h.advance(800);h.fire(800);await flush();if(++polls>40)assert.fail('polling never stopped')}
 await pending;
 assert.ok(polls>=18&&polls<=20,'stopped near 15.5 s, got '+polls+' polls');
 assert.match(h.get('#status').textContent,/did not confirm within 15 seconds/);
 assert.equal(h.rows()[0].children[1].textContent,'Result unconfirmed');
 assert.ok(!scripts[2].includes('22000'));
 assert.match(h.run("explain({code:'command_timeout'})"),/within 15 seconds/);assert.match(h.run("WandFeedback.error('command_timeout')"),/within 15 seconds/);
});
test('note times are dated only when they are not from today',()=>{
 const h=harness();
 assert.match(h.run("noteTime(new Date(2026,10,7,20,14),new Date(2026,10,7,21,0))"),/^at \d/);
 assert.match(h.run("noteTime(new Date(2026,10,6,20,14),new Date(2026,10,7,9,0))"),/^yesterday \d/);
 assert.match(h.run("noteTime(new Date(2026,10,6,23,59),new Date(2026,10,7,0,1))"),/^yesterday /);
});

const reading=(h)=>h.commands.filter(a=>a==='get_state').length;
test('a failed state read shows specific copy and retries at 3 s then 8 s then stops',async()=>{
 const h=harness({devices:[mac(true)]});h.setResultFor('get_state',{status:'failed',error:{code:'something_new'}});await flush();
 assert.equal(h.get('#now-playing').textContent,'Couldn’t read your Mac just now. Trying again shortly.');assert.equal(reading(h),1);
 assert.ok(h.has(3000)&&!h.has(8000));h.advance(3000);await h.fire(3000);await flush();
 assert.equal(reading(h),2);assert.equal(h.get('#now-playing').textContent,'Couldn’t read your Mac just now. Trying again shortly.');
 assert.ok(h.has(8000)&&!h.has(3000));h.advance(8000);await h.fire(8000);await flush();
 assert.equal(reading(h),3);assert.equal(h.get('#now-playing').textContent,'Couldn’t read your Mac just now.');
 assert.ok(!h.has(3000)&&!h.has(8000),'no further automatic retries');
 h.setResultFor('get_state',{status:'failed',error:{code:'device_offline'}});await h.run('refreshState(true)');
 assert.equal(h.get('#now-playing').textContent,'Your Mac is offline. Controls return when Wand is open on it.');
});
test('a retry waits while a command is in flight instead of overlapping it',async()=>{
 const h=harness({devices:[mac(true)]});h.setResultFor('get_state',{status:'failed',error:{code:'something_new'}});await flush();
 h.run('busy=true');h.advance(3000);await h.fire(3000);await flush();
 assert.equal(reading(h),1,'no read while busy');assert.ok(h.has(3000),'the same attempt is queued again');h.run('busy=false');
 h.advance(3000);await h.fire(3000);await flush();assert.equal(reading(h),2);assert.ok(h.has(8000));
});
test('a user action resets the retry budget',async()=>{
 const h=harness({devices:[mac(true)]});h.setResultFor('get_state',{status:'failed',error:{code:'something_new'}});await flush();
 h.advance(3000);await h.fire(3000);await flush();h.advance(8000);await h.fire(8000);await flush();assert.ok(!h.has(3000)&&!h.has(8000));
 await h.run("sendAction('mute')");await flush();
 assert.match(h.get('#status').textContent,/Mac muted/);assert.ok(h.has(3000),'the post-command read failed and may retry again');
});
test('coming back online clears the read failure and forces a fresh read',async()=>{
 const h=harness({devices:[mac(true)]});h.setResultFor('get_state',{status:'failed',error:{code:'something_new'}});await flush();
 assert.match(h.get('#now-playing').textContent,/Couldn’t read/);assert.ok(h.has(3000));
 h.setDevices([mac(false)]);await h.run('devices()');await flush();assert.equal(h.get('#now-playing').textContent,'Mac is offline.');
 const before=reading(h);h.setResultFor('get_state',{status:'succeeded',result:{screen_locked:false,now_playing:{title:'Song',artist:'Band',playing:true},audio:{volume:40,muted:false}}});
 h.setDevices([mac(true)]);await h.run('devices()');await flush();
 assert.equal(reading(h),before+1,'one forced read on the transition');assert.ok(!h.has(3000)&&!h.has(8000));
 assert.equal(h.get('#now-playing').textContent,'Playing · Song · Band');assert.equal(h.get('#mute-state').textContent,'Sound on');
});
test('a stale cached reading is replaced right away when the Mac returns, before the read answers',async()=>{
 const h=harness({devices:[mac(true)]});h.setResultFor('get_state',{status:'failed',error:{code:'something_new'}});await flush();
 h.setDevices([mac(false)]);await h.run('devices()');await flush();
 h.setResultFor('get_state',new Promise(()=>{}));h.setDevices([mac(true)]);h.run('devices()');await flush();
 assert.equal(h.get('#now-playing').textContent,'Checking playback…');assert.ok(!h.has(3000)&&!h.has(8000));
});
test('the app list loader reports read failures with the same copy and retry schedule',async()=>{
 const h=harness({devices:[mac(true)]});await flush();
 h.setResultFor('list_apps',{status:'failed',error:{code:'something_new'}});
 const attempt=async()=>{let error;const pending=h.run("appPicker.load('mac',0)").catch(e=>error=e);await flush();while(!error&&h.has(250)){await h.fire(250);await flush()}await pending;return error};
 let error=await attempt();
 assert.equal(error.message,'Couldn’t read your Mac just now. Trying again shortly.');assert.ok(h.has(3000));
 h.setResultFor('list_apps',{status:'failed',error:{code:'invalid_action'}});error=await attempt();
 assert.match(error.message,/Update Wand on your Mac/,'the update hint is kept verbatim');
});

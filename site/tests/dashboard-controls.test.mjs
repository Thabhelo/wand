import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
const read=f=>fs.readFileSync(new URL('../../web/'+f,import.meta.url),'utf8');
const available={contract_version:1,source:'device',stale:false,actions:['get_state','set_volume','mute','unmute','open_app','quit_app','list_apps','open_url','run_shortcut','lock_screen','media_play_pause','media_next','media_previous'].map(name=>({name,support:'supported',authorized:true,availability:'available',reason:null}))};
async function setup(saved,override={},capabilities=available){
 const dom=new JSDOM(read('index.html'),{url:'https://app.getwand.app',runScripts:'outside-only'}),w=dom.window,commands=[];
 if(saved)w.sessionStorage.setItem('wand-history-tester',saved);
 w.wandAuth={create:async()=>({isAuthenticated:async()=>true,getUser:async()=>({uid:'tester',email:'beta-tester@example.com'}),getTokenSilently:async()=>'fake',logout:async()=>{}})};
 const state={screen_locked:false,frontmost_app:'TextEdit',running_apps:[],now_playing:{title:'Track',artist:'Artist',source_app:'Music'},battery:{percent:16,charging:false},audio:{volume:60,muted:true}};
 Object.assign(state,override);if(override.audio===undefined&&Object.hasOwn(override,'audio'))delete state.audio;
 w.fetch=async(url,options={})=>{let data;if(url==='/config')data={firebase:{apiKey:'fake',projectId:'fake'}};else if(url==='/v1/devices')data=[{device_id:'mac',name:'Test Mac',online:true}];else if(url==='/v1/devices/mac/capabilities')data=capabilities;else if(url==='/v1/connections')data=[];else if(url==='/v1/commands'){commands.push(JSON.parse(options.body));data={command_id:String(commands.length-1)}}else if(url.startsWith('/v1/commands/')){const c=commands[Number(url.split('/').pop())];data={status:'succeeded',result:c.action==='get_state'?state:c.action==='list_apps'?{apps:[],next_offset:null}:{}}}return {ok:true,json:async()=>data}};
 for(const f of ['control-feedback.js','app-picker.js','capability-policy.js','dashboard.js'])w.eval(read(f));
 await new Promise(r=>setTimeout(r,350));return {dom,w,commands};
}
test('dashboard initializes real audio and playback, flags battery, keeps history after reload',async()=>{
 const {dom,w}=await setup(JSON.stringify([{deviceId:'mac',label:'Set volume · 60%',time:new Date(),status:'succeeded'}]));try{
 assert.equal(w.document.querySelector('#volume').value,'60');assert.equal(w.document.querySelector('#volume-value').textContent,'60%');assert.equal(w.document.querySelector('#mute-state').textContent,'Muted');assert.match(w.document.querySelector('#now-playing').textContent,/Track · Artist · Music/);assert.match(w.document.querySelector('.state-warning').textContent,/Low/);assert.match(w.document.querySelector('#activity').textContent,/60%/);assert.ok(w.document.querySelector('[data-action="lock_screen"]'));
 }finally{dom.window.close()}
});
test('slider sends its latest value without a Set button',async()=>{
 const {dom,w,commands}=await setup();try{const slider=w.document.querySelector('#volume');slider.value='61';slider.dispatchEvent(new w.Event('input'));slider.value='63';slider.dispatchEvent(new w.Event('input'));await new Promise(r=>setTimeout(r,350));assert.deepEqual(commands.filter(c=>c.action==='set_volume').map(c=>c.params.level),[63]);assert.equal(w.document.querySelector('#volume-form button'),null)}finally{dom.window.close()}
});
async function until(check){for(let i=0;i<150;i++){if(check())return;await new Promise(r=>setTimeout(r,20))}assert.fail('Dashboard did not reach the expected state')}
test('slider retains focus and coalesces changes while a volume command is in flight',async()=>{
 const {dom,w,commands}=await setup();let release;
 try{
  const slider=w.document.querySelector('#volume'),fetch=w.fetch;
  const held=new Promise(resolve=>release=resolve);
  w.fetch=async(url,options)=>{if(url.startsWith('/v1/commands/')&&commands[Number(url.split('/').pop())]?.action==='set_volume')await held;return fetch(url,options)};
  // Even briefly disabling the range blurs it in browsers; jsdom does not model that behavior.
  const descriptor=Object.getOwnPropertyDescriptor(w.HTMLInputElement.prototype,'disabled'),disabledWrites=[];
  Object.defineProperty(slider,'disabled',{get(){return descriptor.get.call(this)},set(value){disabledWrites.push(value);descriptor.set.call(this,value)}});
  slider.focus();slider.value='61';slider.dispatchEvent(new w.Event('input'));
  await until(()=>commands.some(c=>c.action==='set_volume'));
  assert.equal(slider.disabled,false);assert.equal(w.document.activeElement,slider);
  slider.value='62';slider.dispatchEvent(new w.Event('input'));
  slider.value='63';slider.dispatchEvent(new w.Event('input'));
  assert.equal(w.document.querySelector('#volume-value').textContent,'63%');
  release();await until(()=>commands.filter(c=>c.action==='set_volume').length===2);
  await until(()=>w.document.querySelector('#status').textContent.includes('63%'));
  assert.deepEqual(commands.filter(c=>c.action==='set_volume').map(c=>c.params.level),[61,63]);
  assert.ok(!disabledWrites.includes(true),'Volume sends must never disable the focused slider');
  assert.equal(w.document.activeElement,slider);
 }finally{release?.();await new Promise(r=>setTimeout(r,0));dom.window.close()}
});
test('volume input stops when the Mac loses its capability during a send',async()=>{
 const {dom,w,commands}=await setup();let release;
 try{
  const fetch=w.fetch,slider=w.document.querySelector('#volume'),held=new Promise(resolve=>release=resolve);
  let blocked=false;
  w.fetch=async(url,options)=>{
   if(url==='/v1/devices/mac/capabilities'&&blocked)return {ok:true,json:async()=>({...available,actions:available.actions.map(a=>a.name==='set_volume'?{...a,availability:'blocked',reason:'device_locked'}:a)})};
   if(url.startsWith('/v1/commands/')&&commands[Number(url.split('/').pop())]?.action==='set_volume')await held;
   return fetch(url,options);
  };
  slider.value='61';slider.dispatchEvent(new w.Event('input'));
  await until(()=>commands.some(c=>c.action==='set_volume'));
  slider.value='63';slider.dispatchEvent(new w.Event('input'));
  blocked=true;w.document.querySelector('#refresh').click();
  await until(()=>slider.disabled);
  release();await until(()=>!w.document.querySelector('[data-action="get_state"]').disabled);
  await new Promise(r=>setTimeout(r,1600));
  assert.deepEqual(commands.filter(c=>c.action==='set_volume').map(c=>c.params.level),[61]);
 }finally{release?.();await new Promise(r=>setTimeout(r,0));dom.window.close()}
});
test('dashboard shows this Mac’s reported version and build without guessing missing metadata',async()=>{
 for(const [fields,expected] of [
  [{agent_version:'0.13.1',agent_build:'34'},'Wand 0.13.1 · Build 34'],
  [{agent_version:'0.13.1',agent_build:null},'Wand 0.13.1'],
  [{agent_version:null,agent_build:'34'},'Build 34'],
  [{agent_version:'0.13.1',agent_build:'34',stale:true},'Last reported: Wand 0.13.1 · Build 34'],
  [{source:'unknown'},'Version not reported'],
  [{agent_version:'<b>dev</b>',agent_build:'<i>34</i>'},'Wand <b>dev</b> · Build <i>34</i>']
 ]){
  const {dom,w}=await setup(null,{},{...available,...fields});
  try{const version=w.document.querySelector('#device-version');assert.equal(version.textContent,expected);assert.equal(version.children.length,0)}finally{dom.window.close()}
 }
});
test('switching Macs clears the previous build and ignores its late capability response',async()=>{
 const {dom,w}=await setup(null,{},{...available,agent_version:'0.13.1',agent_build:'34'});let release;
 try{
  const fetch=w.fetch,held=new Promise(resolve=>release=resolve);let pending=false;
  w.fetch=async(url,options)=>{
   if(url==='/v1/devices')return {ok:true,json:async()=>[{device_id:'mac',name:'Test Mac',online:true},{device_id:'other',name:'Other Mac',online:true}]};
   if(url==='/v1/devices/other/capabilities'){pending=true;await held;return {ok:true,json:async()=>({...available,agent_version:'0.12.0',agent_build:'31'})}}
   return fetch(url,options);
  };
  w.document.querySelector('#refresh').click();
  await until(()=>w.document.querySelectorAll('.device').length===2&&!w.document.querySelector('#refresh').disabled);
  w.document.querySelectorAll('.device')[1].click();
  assert.equal(w.document.querySelector('#device-version').textContent,'Version not reported');
  await until(()=>pending);
  w.document.querySelectorAll('.device')[0].click();
  await until(()=>w.document.querySelector('#device-version').textContent==='Wand 0.13.1 · Build 34');
  release();await new Promise(r=>setTimeout(r,30));
  assert.equal(w.document.querySelector('#device-version').textContent,'Wand 0.13.1 · Build 34');
 }finally{release?.();await new Promise(r=>setTimeout(r,0));dom.window.close()}
});
test('missing app selection is reported next to the picker without sending a command',async()=>{
 const {dom,w,commands}=await setup();try{
  const form=w.document.querySelector('#app-form');
  form.dispatchEvent(new w.SubmitEvent('submit',{bubbles:true,cancelable:true,submitter:form.querySelector('button[value="open_app"]')}));
  assert.equal(form.querySelector('#app-error').textContent,'Choose an app first.');
  assert.equal(form.querySelector('#app-error').getAttribute('role'),'alert');
  assert.doesNotMatch(w.document.querySelector('#status').textContent,/Choose an app first/);
  assert.equal(commands.filter(c=>c.action==='open_app').length,0);
 }finally{dom.window.close()}
});
test('support opens the help page instead of an email composer',async()=>{
 const {dom,w}=await setup();try{
  assert.equal(w.document.querySelector('#account').textContent,'beta-tester@example.com');
  const link=w.document.querySelector('footer a[href="https://getwand.app/support"]');
  assert.equal(link.getAttribute('href'),'https://getwand.app/support');
  assert.ok(!link.href.includes('beta-tester@example.com'));
 }finally{dom.window.close()}
});

test('older agents and failed audio reads get different guidance without an unavailable update',async()=>{
 for(const [audio,expected] of [[undefined,'This version of Wand doesn’t report volume yet.'],[null,'Couldn’t read your Mac’s volume.']]){
  const {dom,w}=await setup(null,{audio,now_playing:null,running_apps:[]});try{
   assert.equal(w.document.querySelector('#mute-state').textContent,expected);
   assert.equal(w.document.querySelector('#volume').disabled,true);
   assert.equal(w.document.querySelector('#now-playing').textContent,'Open Music or Spotify on your Mac.');
  }finally{dom.window.close()}
 }
});
test('missing track data does not claim a running player is closed or paused',async()=>{
 const {dom,w}=await setup(null,{now_playing:null,running_apps:['Spotify']});try{
  assert.equal(w.document.querySelector('#now-playing').textContent,'No track information available.');
  assert.doesNotMatch(w.document.querySelector('#state-result').textContent,/Nothing playing/);
 }finally{dom.window.close()}
});

test('capability gaps and unknown legacy support fail closed while status stays usable',async()=>{
 for(const [report,disabled] of [[{stale:false,actions:[{name:'mute',support:'unsupported',authorized:true}]},true],[{stale:true,actions:[{name:'mute',support:'unsupported',authorized:true}]},true],[{stale:true,actions:[{name:'mute',support:'unknown',authorized:true}]},true]]){
  const {dom,w}=await setup(null,{},report);try{assert.equal(w.document.querySelector('[data-action="mute"]').disabled,disabled);assert.equal(w.document.querySelector('[data-action="get_state"]').disabled,false)}finally{dom.window.close()}
 }
});
test('permission-blocked dashboard actions identify the required macOS permission',async()=>{
 const report={...available,stale:false,permissions:{accessibility:'denied',screen_recording:'granted'},actions:available.actions.map(item=>item.name==='lock_screen'?{...item,availability:'blocked',reason:'permission_denied',required_permissions:['accessibility']}:item)};
 const {dom,w,commands}=await setup(null,{},report);
 try{const lock=w.document.querySelector('[data-action="lock_screen"]');assert.equal(lock.disabled,true);assert.match(lock.title,/Accessibility/);assert.doesNotMatch(lock.title,/Screen Recording/);assert.equal(commands.filter(c=>c.action==='lock_screen').length,0)}finally{dom.window.close()}
});

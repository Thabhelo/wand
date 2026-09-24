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

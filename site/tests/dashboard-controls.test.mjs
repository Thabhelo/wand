import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {JSDOM} from 'jsdom';
const read=f=>fs.readFileSync(new URL('../../web/'+f,import.meta.url),'utf8');
async function setup(saved){
 const dom=new JSDOM(read('index.html'),{url:'https://app.getwand.app',runScripts:'outside-only'}),w=dom.window,commands=[];
 if(saved)w.sessionStorage.setItem('wand-history-tester',saved);
 w.wandAuth={create:async()=>({isAuthenticated:async()=>true,getUser:async()=>({uid:'tester'}),getTokenSilently:async()=>'fake',logout:async()=>{}})};
 const state={screen_locked:false,frontmost_app:'TextEdit',running_apps:[],now_playing:{title:'Track',artist:'Artist',source_app:'Music'},battery:{percent:16,charging:false},audio:{volume:60,muted:true}};
 w.fetch=async(url,options={})=>{let data;if(url==='/config')data={firebase:{apiKey:'fake',projectId:'fake'}};else if(url==='/v1/devices')data=[{device_id:'mac',name:'Test Mac',online:true}];else if(url==='/v1/connections')data=[];else if(url==='/v1/commands'){commands.push(JSON.parse(options.body));data={command_id:String(commands.length-1)}}else if(url.startsWith('/v1/commands/')){const c=commands[Number(url.split('/').pop())];data={status:'succeeded',result:c.action==='get_state'?state:c.action==='list_apps'?{apps:[],next_offset:null}:{}}}return {ok:true,json:async()=>data}};
 for(const f of ['control-feedback.js','app-picker.js','dashboard.js'])w.eval(read(f));
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

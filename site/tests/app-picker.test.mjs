import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
const source=readFileSync(new URL('../../web/app-picker.js',import.meta.url),'utf8');
function setup(load,current=false){const dom=new JSDOM('<div id="root"></div>',{runScripts:'outside-only'});dom.window.eval(source);return new dom.window.WandAppPicker(dom.window.document.getElementById('root'),{load,current})}
const app=(name,id)=>({name,bundle_id:id,running:false,last_opened:null});
test('loads every page in server recency order, uses IDs and supports manual fallback',async()=>{
 const calls=[];const picker=setup(async(id,offset)=>{calls.push([id,offset]);return offset?{apps:[app('Same','a.two')],next_offset:null}:{apps:[app('Same','a.one')],next_offset:100}});
 await picker.setDevice('mac1');assert.deepEqual(calls,[['mac1',0],['mac1',100]]);assert.equal(picker.apps.length,2);
 picker.select.value='a.two';assert.equal(picker.value().params.bundle_id,'a.two');assert.match(picker.select.options[1].textContent,/a.one/);
 picker.select.value='__manual';picker.select.onchange();picker.manual.value='My Editor';assert.equal(picker.value().params.app_name,'My Editor');assert.equal(picker.manual.hidden,false);
 picker.manual.value='com.example.Editor';assert.equal(picker.value().params.bundle_id,'com.example.Editor');
});
test('late response from another Mac never replaces the selected Mac catalog',async()=>{
 let release;const picker=setup(id=>id==='old'?new Promise(r=>release=r):Promise.resolve({apps:[app('New','app.new')],next_offset:null}));
 const pending=picker.setDevice('old');await picker.setDevice('new');release({apps:[app('Old','app.old')],next_offset:null});await pending;
 assert.equal(picker.apps[0].bundle_id,'app.new');assert.equal(picker.apps.length,1);
});
test('offline state clears inventory, and failures leave Other usable',async()=>{
 const picker=setup(async()=>{throw Error('Update Wand on your Mac.')});await picker.setDevice('mac');assert.match(picker.note.textContent,/Update/);assert.equal(picker.select.options[1].value,'__manual');
 await picker.setDevice('mac',false,false);assert.equal(picker.apps.length,0);assert.match(picker.note.textContent,/offline/);assert.equal(picker.retry.disabled,true);
});
test('app labels render as text',async()=>{
 const picker=setup(async()=>({apps:[app('<img onerror=alert(1)>','app.one'),app('Other editor','app.two')],next_offset:null}));await picker.setDevice('mac');assert.equal(picker.select.options[1].textContent,'<img onerror=alert(1)>');assert.equal(picker.select.querySelector('img'),null);
});

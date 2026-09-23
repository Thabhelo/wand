import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const scope={};vm.runInNewContext(fs.readFileSync(new URL('../../web/control-feedback.js',import.meta.url),'utf8'),scope);
const f=scope.WandFeedback;
test('protects session components but keeps ordinary apps',()=>{
 for(const name of ['loginwindow','Dock','WindowManager','SystemUIServer','SecurityAgent'])assert.equal(f.safeApp({name,bundle_id:'com.apple.'+name}),false);
 assert.equal(f.safeApp({name:'Chrome',bundle_id:'com.google.Chrome'}),true);
});
test('feedback distinguishes no-ops and actual focus',()=>{
 assert.equal(f.success('quit_app',{already_closed:true}),'App was already closed.');
 assert.equal(f.success('open_app',{already_open:true,focused:true}),'Already open. Brought to front.');
 assert.equal(f.success('open_app',{already_open:true,focused:false}),'App is already open.');
 assert.equal(f.success('set_volume',{},null,{level:60}),'Volume set to 60%.');
});

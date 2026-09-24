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
test('permission feedback describes denial without claiming the user never approved it',()=>{
 const message=f.error('accessibility_permission_required');
 assert.match(message,/macOS isn’t allowing Wand/);
 assert.doesNotMatch(message,/not enabled|never approved|reinstall|reset|quit/i);
 assert.doesNotMatch(message,/accessibility_permission_required/);
});
test('unknown wire errors never become customer-facing codes',()=>{
 for(const code of ['new_internal_error',undefined,'constructor','__proto__'])assert.equal(f.error(code),'Wand couldn’t confirm the result. Check your Mac before trying again.');
});
test('desktop controls and confirmations use human labels',()=>{
 assert.equal(f.role('AXTextArea'),'Text area');
 assert.equal(f.role('AXFutureControl'),'Control');
 assert.equal(f.interaction({operation:'key',key:'select_all'}),'Send “Select all” to this app.');
 assert.equal(f.interaction({operation:'key',key:'future_raw_key'}),'Send the selected key to this app.');
 assert.equal(f.interaction({operation:'click',click_count:2}),'Double-click this point in the app.');
});

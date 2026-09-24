import {test} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const context={window:{}};vm.runInNewContext(fs.readFileSync(new URL('../../web/capability-policy.js',import.meta.url),'utf8'),context);
const policy=context.window.WandCapabilities;
const report={contract_version:1,stale:false,online:true,actions:[{name:'mute',support:'supported',authorized:true,availability:'available',reason:null}]};
test('unknown, stale and future-version reports cannot enable actions',()=>{
 for(const r of [null,{...report,stale:true},{...report,contract_version:2},{...report,actions:[]}])assert.ok(policy.reason(r,'mute'));
 assert.equal(policy.reason(report,'mute'),null);
 assert.equal(policy.reason(null,'get_state'),null);
 assert.equal(policy.reason(null,'desktop_stop'),null);
});
test('status fallback never bypasses an explicit scope denial',()=>{
 assert.equal(policy.reason({...report,actions:[{name:'get_state',authorized:false}]},'get_state'),'not_authorized');
 const denied={...report,actions:[{...report.actions[0],availability:'blocked',reason:'disabled_by_user'}]};
 assert.equal(policy.reason(denied,'mute'),'disabled_by_user');
 assert.match(policy.message('disabled_by_user'),/Enable desktop control/);
});
test('both web entry points load the shared capability policy',()=>{
 for(const path of ['../../web/index.html','../public/desktop/index.html'])assert.match(fs.readFileSync(new URL(path,import.meta.url),'utf8'),/src="\/capability-policy.js"/);
});
test('permission guidance names the denied permission required by the requested feature',()=>{
 const image={required_permissions:['desktop_control','accessibility','screen_recording']};
 const observe={required_permissions:['desktop_control','accessibility']};
 const captureDenied={...report,permissions:{desktop_control:'granted',accessibility:'granted',screen_recording:'denied'}};
 const message=policy.message('permission_denied',captureDenied,image);
 assert.match(message,/Screen Recording/);
 assert.match(message,/turn off images/);
 assert.doesNotMatch(message,/Accessibility/);
 assert.equal(policy.message('permission_denied',captureDenied,observe),policy.messages.permission_denied);
 const axDenied={...captureDenied,permissions:{...captureDenied.permissions,accessibility:'denied',screen_recording:'granted'}};
 assert.match(policy.message('permission_denied',axDenied,observe),/Accessibility/);
 assert.doesNotMatch(policy.message('permission_denied',axDenied,observe),/Screen Recording/);
 const bothDenied={...captureDenied,permissions:{...captureDenied.permissions,accessibility:'denied'}};
 assert.match(policy.message('permission_denied',bothDenied,image),/Accessibility and Screen Recording/);
});
test('incomplete or stale permission reports never invent a permission-specific fix',()=>{
 const entry={required_permissions:['screen_recording']};
 for(const data of [null,{...report,permissions:{screen_recording:'unknown'}},{...report,stale:true,permissions:{screen_recording:'denied'}},{...report,online:false,permissions:{screen_recording:'denied'}},{...report,contract_version:2,permissions:{screen_recording:'denied'}}]){
  assert.equal(policy.message('permission_denied',data,entry),policy.messages.permission_denied);
 }
 assert.equal(policy.message('permission_denied',report,{}),policy.messages.permission_denied);
 assert.equal(policy.message('constructor'),'This action is unavailable. Refresh and try again.');
});

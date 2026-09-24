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

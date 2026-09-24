import {describe,it,expect} from 'vitest';
import {deviceCapabilities} from '../src/capabilities.js';
import {validate} from '../src/common.js';
const report={schema_version:1,agent_version:'test',agent_build:'42',os_version:'26',screen_state:'unlocked',actions:['get_state','lock_screen','mute','desktop_act','desktop_observe','desktop_stop','toggle_do_not_disturb'],features:['audio_output_state','desktop_images'],permissions:{desktop_control:'granted',accessibility:'granted',screen_recording:'denied'}};
const doc=(r=report,online=true,at=new Date().toISOString(),allowed=null)=>deviceCapabilities('00000000-0000-4000-8000-000000000001',online,r,at,allowed,3);
const action=(d,name='desktop_act')=>d.actions.find(a=>a.name===name);
describe('capability planning contract',()=>{
 it('separates support, consent and availability, including image-only permission',()=>{
  const d=doc();validate('DeviceCapabilities',d);expect(d.contract_version).toBe(1);expect(d.revision).toBe(3);
  expect(action(d).availability).toBe('available');expect(d.feature_status.desktop_images.reason).toBe('permission_denied');
  const scoped=doc(report,true,undefined,['get_state']);expect(action(scoped).support).toBe('supported');expect(action(scoped).authorized).toBe(false);expect(action(scoped).reason).toBe('not_authorized');
 });
 it('explains disabled control, denied and unknown permissions without changing support',()=>{
  for(const [permissions,reason] of [[{desktop_control:'denied'},'disabled_by_user'],[{accessibility:'denied'},'permission_denied'],[{accessibility:'unknown'},'permission_unknown']]){
   const a=action(doc({...report,permissions:{...report.permissions,...permissions}}));expect(a.support).toBe('supported');expect(a.reason).toBe(reason);
  }
 });
 it('fails closed for missing reports, stale timestamps and offline devices',()=>{
  expect(action(doc(null)).reason).toBe('capability_unreported');
  for(const at of ['invalid',new Date(Date.now()-76000).toISOString(),new Date(Date.now()+60000).toISOString()]){const d=doc(report,true,at);expect(d.stale).toBe(true);expect(action(d).reason).toBe('stale_report');expect(d.permissions.accessibility).toBe('unknown')}
  expect(action(doc(report,false)).reason).toBe('device_offline');
 });
 it('keeps lock idempotent and stop accessible while blocking private state/features',()=>{
  const d=doc({...report,screen_state:'locked'});expect(action(d).reason).toBe('device_locked');expect(action(d,'lock_screen').availability).toBe('available');expect(action(d,'desktop_stop').availability).toBe('available');expect(action(d,'get_state').availability).toBe('available');expect(d.feature_status.audio_output_state.reason).toBe('device_locked');
 });
 it('allows additive response fields without allowing arbitrary commands',()=>{
  const d=doc();d.future_metadata=true;d.features.future_feature='unknown';d.actions.push({...action(d),name:'future_action'});validate('DeviceCapabilities',d);
  expect(()=>validate('CommandRequest',{device_id:d.device_id,action:'future_action',params:{}})).toThrow();
 });
});

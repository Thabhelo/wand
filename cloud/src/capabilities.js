import catalog from '../../contracts/actions.json' with {type:'json'};
export const FEATURES=['audio_output_state','playback_state','app_inventory','desktop_images','system_status'];
const featureActions={audio_output_state:'get_state',playback_state:'get_state',app_inventory:'list_apps',desktop_images:'desktop_observe',system_status:'get_state'};
// Stable serialization makes revision changes independent of JSON object/array ordering.
export function serializeReport(report){
 if(!report)return 'null';
 const normalized={...report,actions:[...report.actions].sort(),features:[...report.features].sort()};
 function sort(value){return Array.isArray(value)?value.map(sort):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(k=>[k,sort(value[k])])):value}
 return JSON.stringify(sort(normalized));
}
// These are preconditions we can observe without prompting. Execution still checks
// target-specific Automation consent, Shortcut allowlists and current OS state.
function requirements(name){return name==='desktop_images'?['desktop_control','accessibility','screen_recording']:['desktop_observe','desktop_act'].includes(name)?['desktop_control','accessibility']:['toggle_do_not_disturb','lock_screen'].includes(name)?['accessibility']:[]}
export function deviceCapabilities(device_id,online,report,reported_at,allowedActions=null,revision=0){
 const age=Date.now()-Date.parse(reported_at);
 const stale=!online||!report||!Number.isFinite(age)||age<0||age>75000;
 const permissions=Object.fromEntries(['desktop_control','accessibility','screen_recording'].map(name=>[name,stale?'unknown':report.permissions[name]]));
 const support=(items,name)=>report?(items.includes(name)?'supported':'unsupported'):'unknown';
 function describe(name,implemented,action){
  const authorized=!allowedActions||allowedActions.includes(action),required_permissions=name==='lock_screen'&&report?.screen_state==='locked'?[]:requirements(name);
  let reason=null,availability='available';
  if(!authorized)reason='not_authorized';
  else if(implemented==='unsupported')reason='unsupported_build';
  else if(!online)reason='device_offline';
  else if(!report||implemented==='unknown')reason='capability_unreported';
  else if(stale)reason='stale_report';
  else if(!['get_state','lock_screen','desktop_stop'].includes(name)&&report.screen_state==='locked')reason='device_locked';
  else if(!['get_state','lock_screen','desktop_stop'].includes(name)&&['unknown','inactive'].includes(report.screen_state))reason='session_unavailable';
  else if(required_permissions.includes('desktop_control')&&permissions.desktop_control==='denied')reason='disabled_by_user';
  else if(required_permissions.some(p=>permissions[p]==='denied'))reason='permission_denied';
  else if(required_permissions.some(p=>permissions[p]!=='granted'))reason='permission_unknown';
  if(reason)availability=['capability_unreported','stale_report','permission_unknown','session_unavailable'].includes(reason)?'unknown':'blocked';
  return {support:implemented,authorized,availability,reason,required_permissions};
 }
 const actions=catalog.map(({name})=>({name,...describe(name,support(report?.actions,name),name)}));
 const features=Object.fromEntries(FEATURES.map(name=>[name,support(report?.features,name)]));
 return {contract_version:1,revision,device_id,online,source:report?'device':'unknown',reported_at:report?reported_at:null,stale,
  agent_version:report?.agent_version??null,agent_build:report?.agent_build??null,os_version:report?.os_version??null,
  actions,features,feature_status:Object.fromEntries(FEATURES.map(name=>[name,describe(name,features[name],featureActions[name])])),permissions};
}

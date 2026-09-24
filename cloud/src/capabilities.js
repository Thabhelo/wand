import catalog from '../../contracts/actions.json' with {type:'json'};
export const FEATURES=['audio_output_state','playback_state','app_inventory','desktop_images','system_status'];
export function deviceCapabilities(device_id,online,report,reported_at,allowedActions=null){
 const stale=!online||!report||!reported_at||Date.now()-Date.parse(reported_at)>75000;
 const support=(items,name)=>report?(items.includes(name)?'supported':'unsupported'):'unknown';
 const actions=catalog.map(({name})=>({name,support:support(report?.actions,name),authorized:!allowedActions||allowedActions.includes(name)}));
 return {device_id,online,source:report?'device':'unknown',reported_at:report?reported_at:null,stale,
  agent_version:report?.agent_version??null,agent_build:report?.agent_build??null,actions,
  features:Object.fromEntries(FEATURES.map(name=>[name,support(report?.features,name)])),
  permissions:Object.fromEntries(['desktop_control','accessibility','screen_recording'].map(name=>[name,stale?'unknown':report.permissions[name]]))};
}

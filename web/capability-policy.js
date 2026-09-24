/* One interpretation for the dashboard and desktop controls. Unknown never means ready. */
window.WandCapabilities={
 messages:{unsupported_build:'This build does not support this action.',not_authorized:'Allow this action in your Wand connection first.',device_offline:'Your Mac is offline.',capability_unreported:'This build does not report its capabilities yet. You can still check Mac status.',stale_report:'Checking what your Mac can do. Refresh and try again.',device_locked:'Unlock your Mac in person first.',session_unavailable:'Return to your Mac’s active session first.',disabled_by_user:'Enable desktop control in Wand on your Mac.',permission_denied:'Allow the required permission in System Settings → Privacy & Security.',permission_unknown:'Wand cannot confirm this Mac’s permissions yet.'},
 reason(report,action){
  const item=report?.actions?.find(a=>a.name===action);
  if(item?.authorized===false)return 'not_authorized';
  if(item?.support==='unsupported')return 'unsupported_build';
  // Status discovers a legacy device; Stop must remain reachable as a safety control.
  if(['get_state','desktop_stop'].includes(action))return null;
  if(!report||report.contract_version!==1||item?.support!=='supported')return 'capability_unreported';
  if(report.stale)return report.online===false?'device_offline':'stale_report';
  return item.availability==='available'?null:item.reason||'capability_unreported';
 },
 message(reason){return this.messages[reason]||'This action is unavailable. Refresh and try again.'}
};

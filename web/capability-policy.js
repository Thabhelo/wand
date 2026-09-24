/* One interpretation for the dashboard and desktop controls. Unknown never means ready. */
window.WandCapabilities={
 messages:{unsupported_build:'This build does not support this action.',not_authorized:'Allow this action in your Wand connection first.',device_offline:'Your Mac is offline.',capability_unreported:'This build does not report its capabilities yet. You can still check Mac status.',stale_report:'Checking what your Mac can do. Refresh and try again.',device_locked:'Unlock your Mac in person first.',session_unavailable:'Return to your Mac’s active session first.',disabled_by_user:'Enable desktop control in Wand on your Mac.',permission_denied:'macOS is denying Wand a required permission. Check Wand in System Settings → Privacy & Security.',permission_unknown:'Wand cannot confirm this Mac’s permissions yet.'},
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
 message(reason,report,entry){
  // Name only denied permissions required by this action or optional feature.
  if(reason==='permission_denied'&&report?.contract_version===1&&report.stale===false&&report.online!==false&&Array.isArray(entry?.required_permissions)){
   const denied=entry.required_permissions.filter(name=>report.permissions?.[name]==='denied');
   const accessibility=denied.includes('accessibility'),screen=denied.includes('screen_recording');
   if(accessibility&&screen)return 'macOS isn’t allowing Wand to control or capture apps. Check Accessibility and Screen Recording in System Settings → Privacy & Security. You can turn off images to skip Screen Recording.';
   if(accessibility)return 'macOS isn’t allowing Wand to control apps. Check Wand in System Settings → Privacy & Security → Accessibility.';
   if(screen)return 'macOS isn’t allowing Wand to capture app windows. Check Wand in System Settings → Privacy & Security → Screen Recording, or turn off images.';
  }
  return Object.hasOwn(this.messages,reason)?this.messages[reason]:'This action is unavailable. Refresh and try again.';
 }
};

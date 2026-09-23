/* Shared, plain-language feedback. Never display an unknown wire error verbatim. */
(function(root){
 const messages={protected_app:'This is a macOS component. Wand cannot open or close it.',app_not_found_or_ambiguous:'App not found. Refresh the app list and choose it again.',app_not_found:'This app is not installed on your Mac.',quit_refused:'Your Mac could not close this app.',quit_pending_user_attention:'Save or dismiss the open dialog on your Mac, then try again.',media_app_not_running:'Open Music or Spotify on your Mac first.',automation_failed_or_permission_required:'Allow Wand to control this app in your Mac’s Privacy & Security settings.',action_timeout_outcome_unknown:'Your Mac did not confirm the result. Check it before retrying.',action_failed:'Your Mac could not complete this action. Try again.',invalid_params:'Check your selection and try again.'};
 const protectedNames=new Set(['loginwindow','dock','windowmanager','systemuiserver','controlcenter','securityagent','loginitems','spotlight','universalcontrol']);
 root.WandFeedback={messages,safeApp:app=>!protectedNames.has((app.name||'').toLowerCase())&&!/^com\.apple\.(loginwindow|dock|windowmanager|systemuiserver|controlcenter|securityagent)(\.|$)/i.test(app.bundle_id||''),
 success(action,data={},label='App',params={}){
  if(action==='open_app')return data.already_open?(data.focused?'Already open. Brought to front.':'App is already open.'):'App opened.';
  if(action==='quit_app')return data.already_closed?'App was already closed.':'App closed.';
  if(action==='lock_screen')return data.already_locked?'Mac was already locked.':'Mac locked.';
  if(action==='set_volume')return `Volume set to ${params.level}%.`;
  return ({mute:'Mac muted.',unmute:'Mac unmuted.',get_state:'Mac status updated.',open_url:'Website opened.',run_shortcut:'Shortcut finished.',media_play_pause:'Playback changed.',media_next:'Skipped to next track.',media_previous:'Returned to previous track.'})[action]||'Done.';
 }};
})(typeof window==='undefined'?globalThis:window);

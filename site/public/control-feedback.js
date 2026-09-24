/* Shared, plain-language feedback. Never display an unknown wire error verbatim. */
(function(root){
 const messages={protected_app:'This is a macOS component. Wand cannot open or close it.',app_not_found_or_ambiguous:'App not found. Refresh the app list and choose it again.',app_not_found:'This app is not installed on your Mac.',quit_refused:'Your Mac could not close this app.',quit_pending_user_attention:'Save or dismiss the open dialog on your Mac, then try again.',media_app_not_running:'Open Music or Spotify on your Mac first.',automation_failed_or_permission_required:'Allow Wand to control this app in your Mac’s Privacy & Security settings.',action_timeout_outcome_unknown:'Your Mac did not confirm the result. Check it before retrying.',action_failed:'Your Mac could not complete this action. Try again.',invalid_params:'Check your selection and try again.'};
 const protectedNames=new Set(['loginwindow','dock','windowmanager','systemuiserver','controlcenter','securityagent','loginitems','spotlight','universalcontrol']);
 Object.assign(messages,{
  accessibility_permission_required:'macOS isn’t allowing Wand to control apps. Check Wand in System Settings → Privacy & Security → Accessibility.',
  desktop_permission_required:'Enable desktop control in Wand on your Mac.',
  screen_recording_permission_required:'Allow Screen Recording for Wand, or turn off the image option.',
  desktop_window_unavailable:'Open a window in this app, then look again.',
  desktop_capture_window_mismatch:'The window moved or changed. Look again once it stops moving.',
  desktop_capture_failed:'Wand could not capture this window. Look again, or turn off the image option.',
  desktop_image_too_large:'This window could not fit in an image. Try a smaller window or turn off images.',
  desktop_observation_too_large:'This app has too many controls to show at once. Try a smaller window.',
  desktop_image_required:'Look at the app with the image option enabled before clicking its image.',
  desktop_snapshot_expired:'This view expired. Look at the app again.',
  desktop_focus_changed:'The active app or window changed. Look at the app again.',
  desktop_app_not_allowed:'Allow this app in Wand on your Mac first.',
  desktop_app_not_running:'Open this app on your Mac first.',
  desktop_app_excluded:'Wand cannot control this protected app.',
  desktop_protected_ui:'Wand cannot interact with this protected control.',
  desktop_target_not_editable:'This field does not support text replacement. Try typing at the cursor.',
  desktop_target_unavailable:'This control changed. Look at the app again.',
  desktop_action_failed:'The app did not accept that action. Look again before retrying.',
  desktop_busy:'Wand is checking this app. Wait a moment, then try again.',
  device_offline:'Your Mac is offline. Open Wand on it and check its internet connection.',
  device_locked:'Your Mac is locked. Unlock it in person before sending this action.',
  session_unavailable:'Return to your Mac’s active session, then try again.',
  device_token_revoked:'This Mac has been disconnected. Connect it again from Wand.',
  action_unsupported:'This version of Wand does not support this action.',
  action_unavailable:'This action is unavailable on this Mac.',
  action_not_allowlisted:'Add this Shortcut to the allowed list in Wand on your Mac first.',
  permission_required:'Allow this action in Wand on your Mac, then try again.',
  rate_limited:'Too many requests. Wait a minute, then try again.',
  unauthorized:'Please sign out and sign in again.',
  result_expired:'This result is no longer available. Check your Mac before trying again.',
  command_timeout:'Your Mac did not confirm the result in time. Check it before retrying.'
 });
 const keyNames={return:'Return',tab:'Tab',escape:'Escape',up:'Up arrow',down:'Down arrow',left:'Left arrow',right:'Right arrow',backspace:'Delete',space:'Space',select_all:'Select all',home:'Home',end:'End',page_up:'Page up',page_down:'Page down'};
 const roleNames={AXWindow:'Window',AXButton:'Button',AXCheckBox:'Checkbox',AXRadioButton:'Option',AXTextField:'Text field',AXTextArea:'Text area',AXComboBox:'Combo box',AXStaticText:'Text',AXMenuBar:'Menu bar',AXMenu:'Menu',AXMenuItem:'Menu item',AXScrollArea:'Scroll area',AXWebArea:'Web content',AXLink:'Link',AXImage:'Image',AXGroup:'Group',AXToolbar:'Toolbar',AXSplitGroup:'Split view',AXRow:'Row',AXCell:'Cell',AXSlider:'Slider',AXPopUpButton:'Pop-up menu',AXTabGroup:'Tabs',AXTable:'Table',AXList:'List'};
 root.WandFeedback={messages,safeApp:app=>!protectedNames.has((app.name||'').toLowerCase())&&!/^com\.apple\.(loginwindow|dock|windowmanager|systemuiserver|controlcenter|securityagent)(\.|$)/i.test(app.bundle_id||''),
 error(code){return Object.hasOwn(messages,code)?messages[code]:'Wand couldn’t confirm the result. Check your Mac before trying again.'},
 role(role){return Object.hasOwn(roleNames,role)?roleNames[role]:'Control'},
 interaction(params){
  if(params.operation==='type')return 'Replace the selected field with: '+params.text;
  if(params.operation==='type_text')return 'Type at the cursor: '+params.text;
  if(params.operation==='key')return Object.hasOwn(keyNames,params.key)?'Send “'+keyNames[params.key]+'” to this app.':'Send the selected key to this app.';
  if(params.operation==='scroll')return params.direction==='up'?'Scroll up in this app.':'Scroll down in this app.';
  if(params.operation==='click')return params.button==='right'?'Right-click this point in the app.':params.click_count===2?'Double-click this point in the app.':'Click this point in the app.';
  return 'Press the selected control in this app.';
 },
 success(action,data={},label='App',params={}){
  if(action==='open_app')return data.already_open?(data.focused?'Already open. Brought to front.':'App is already open.'):'App opened.';
  if(action==='quit_app')return data.already_closed?'App was already closed.':'App closed.';
  if(action==='lock_screen')return data.already_locked?'Mac was already locked.':'Mac locked.';
  if(action==='set_volume')return `Volume set to ${params.level}%.`;
  return ({mute:'Mac muted.',unmute:'Mac unmuted.',get_state:'Mac status updated.',open_url:'Website opened.',run_shortcut:'Shortcut finished.',media_play_pause:'Playback changed.',media_next:'Skipped to next track.',media_previous:'Returned to previous track.'})[action]||'Done.';
 }};
})(typeof window==='undefined'?globalThis:window);

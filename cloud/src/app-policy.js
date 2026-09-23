// Protect existing agent versions too. Native builds additionally check bundle paths.
export function protectedApp(action,params){
 if(!['open_app','quit_app'].includes(action))return false;
 const name=(params.app_name||'').trim().replace(/\.app$/i,'').toLowerCase();
 return ['loginwindow','dock','windowmanager','systemuiserver','controlcenter','securityagent','loginitems','spotlight','universalcontrol'].includes(name)||/^com\.apple\.(loginwindow|dock|windowmanager|systemuiserver|controlcenter|securityagent)(\.|$)/i.test(params.bundle_id||'');
}

// Owner notices sent through the Workers send_email binding. Deploying without the binding or a sender is safe: nothing is sent and nothing throws.
export const DEFAULT_MAIL_FROM='wand@getwand.app';
export const DASHBOARD_URL='https://app.getwand.app';
const MONTHS=['January','February','March','April','May','June','July','August','September','October','November','December'];
const pad=n=>String(n).padStart(2,'0');
export function formatUtc(ms){const d=new Date(ms);return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()} at ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())} UTC`}
export function relative(ms,now=Date.now()){
 const minutes=Math.max(0,Math.round((now-ms)/60000));
 if(minutes<2)return 'a moment ago';
 if(minutes<60)return `${minutes} minutes ago`;
 const hours=Math.round(minutes/60);
 if(hours<2)return 'about an hour ago';
 if(hours<48)return `about ${hours} hours ago`;
 const days=Math.round(hours/24);
 return `about ${days} days ago`;
}
const escape=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'})[c]);
// Same voice as the dashboard: plain, warm, no exclamation marks.
export function offlineEmail({to,deviceName,lastSeen,now=Date.now()}){
 const seen=typeof lastSeen==='number'?lastSeen:Date.parse(lastSeen);
 const when=formatUtc(seen),ago=relative(seen,now);
 const subject=`Wand on ${deviceName} has been offline since ${when}`;
 const lines=[
  `Wand on ${deviceName} was last seen on ${when}, ${ago}, and has been offline since then.`,
  `Commands from your phone or from Muse will fail until Wand is opened on that Mac again.`,
  `We send this once per outage, so you will not hear more about this one.`,
  `You receive this because ${to} owns this Mac in Wand. Disconnect the Mac at ${DASHBOARD_URL} to stop these.`
 ];
 const text=lines.join('\n\n')+'\n';
 const html=`<!doctype html><html><body style="font-family:-apple-system,system-ui,sans-serif;color:#1c1c1c;line-height:1.5;max-width:36em;margin:2em auto;padding:0 1em">`
  +`<p>${escape(lines[0])}</p><p>${escape(lines[1])}</p><p>${escape(lines[2])}</p>`
  +`<p style="color:#6b6b6b;font-size:0.9em">You receive this because ${escape(to)} owns this Mac in Wand. Disconnect the Mac at <a href="${DASHBOARD_URL}" style="color:#6b6b6b">${DASHBOARD_URL.replace('https://','')}</a> to stop these.</p>`
  +`</body></html>`;
 return {subject,text,html};
}
// Returns {sent:true,messageId} after a send, or {sent:false,reason} when email is not configured. Provider errors are thrown to the caller.
export async function sendOfflineEmail(env,{to,deviceName,lastSeen}){
 const from=env.MAIL_FROM===undefined?DEFAULT_MAIL_FROM:env.MAIL_FROM;
 if(typeof env.EMAIL?.send!=='function'||!from||!to){console.warn(JSON.stringify({event:'offline_email_skipped',reason:'email_not_configured'}));return {sent:false,reason:'email_not_configured'}}
 const message=offlineEmail({to,deviceName,lastSeen});
 const result=await env.EMAIL.send({to,from:{email:from,name:'Wand'},subject:message.subject,text:message.text,html:message.html});
 // Logs carry no address or device name.
 console.log(JSON.stringify({event:'offline_email_sent'}));
 return {sent:true,messageId:result?.messageId??null};
}

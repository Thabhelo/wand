const $=id=>document.getElementById(id);
let auth, device, deviceToken, ws, heartbeat, locked=false;
const show=value=>{$('output').textContent=typeof value==='string'?value:JSON.stringify(value,null,2)};
async function api(path,method='GET',data,bearer){const r=await fetch(path,{method,headers:{'Content-Type':'application/json',...(bearer===null?{}:{Authorization:'Bearer '+(bearer||await auth.getTokenSilently())})},body:data?JSON.stringify(data):undefined});const v=await r.json();if(!r.ok)throw Error(JSON.stringify(v));return v}
function capabilities(){return {schema_version:1,agent_version:'review-simulator-1',agent_build:null,os_version:'synthetic',screen_state:locked?'locked':'unlocked',actions:['get_state','lock_screen','mute','run_shortcut'],features:[],permissions:{desktop_control:'denied',accessibility:'granted',screen_recording:'denied'}}}
function send(type,fields={}){ws.send(JSON.stringify({v:1,type,id:crypto.randomUUID(),ts:new Date().toISOString(),...fields}))}
function disconnect(){clearInterval(heartbeat);if(ws)ws.close(1000,'reviewer_offline');$('status').textContent='Test Mac offline';}
function connect(){return new Promise((resolve,reject)=>{
 ws=new WebSocket('wss://app.getwand.app/review-device?device_id='+device.device_id);
 const timer=setTimeout(()=>{ws.close();reject(Error('Connection timed out. Try reconnecting.'))},10000);
 ws.onopen=()=>send('hello',{device_token:deviceToken,agent_version:'review-simulator-1',device_name:'Simulated review Mac',macos_version:'synthetic',capabilities:capabilities()});
 ws.onerror=()=>{clearTimeout(timer);reject(Error('Device socket failed'))};
 ws.onclose=()=>{clearTimeout(timer);clearInterval(heartbeat);$('status').textContent='Test Mac offline';};
 ws.onmessage=event=>{const m=JSON.parse(event.data);
  if(m.type==='ready'){clearTimeout(timer);$('status').textContent='Simulated Mac online';heartbeat=setInterval(()=>send('heartbeat',{capabilities:capabilities()}),25000);resolve();return}
  if(m.type==='revoke'){deviceToken=null;disconnect();$('status').textContent='Test Mac revoked';return}
  if(m.type!=='command')return;
  send('delivered',{command_id:m.command_id});let data={},error;
  if(Date.parse(m.expires_at)<Date.now()-5000)error='command_expired';
  else if(m.action==='lock_screen'){data={already_locked:locked};locked=true}
  else if(m.action==='get_state')data=locked?{screen_locked:true}:{screen_locked:false,frontmost_app:'Synthetic Finder',now_playing:null,battery:{percent:80,charging:true},running_apps:['Synthetic Finder']};
  else if(locked)error='device_locked';
  else if(m.action==='run_shortcut'&&m.params.name!=='Review Demo')error='action_not_allowlisted';
  else if(!['mute','run_shortcut'].includes(m.action))error='action_not_supported';
  send('result',{command_id:m.command_id,ok:!error,...(error?{error_code:error}:{data})});
  send('heartbeat',{capabilities:capabilities()});
 };
})}
function handler(id,fn){$(id).onclick=async()=>{$(id).disabled=true;try{await fn()}catch(e){show(e.message)}finally{$(id).disabled=false}}}
handler('login',()=>auth.loginWithRedirect());
handler('create',async()=>{
 if(device)throw Error('Revoke the current test Mac first.');
 device=await api('/v1/pairing/code','POST',{device_name:'Simulated review Mac',kind:'mac',agent_version:'review-simulator-1'},null);
 $('controls').hidden=false;
 await api('/v1/pairing/claim','POST',{code:device.code});
 deviceToken=btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
 await api('/v1/pairing/redeem','POST',{device_token:deviceToken},device.bootstrap_token);delete device.bootstrap_token;delete device.code;
 locked=false;await connect();show({status:'paired',device_id:device.device_id,simulation:true});
});
handler('run',async()=>{if(!device)throw Error('Create a test Mac first');let action=$('action').value;const params=action==='run_shortcut'?{name:'Review Demo'}:action==='reject'?{name:'Not approved'}:{};if(action==='reject')action='run_shortcut';if(['lock_screen','run_shortcut'].includes(action)&&!confirm('Run '+action+' on the simulated Mac?'))return;const accepted=await api('/v1/commands','POST',{device_id:device.device_id,action,params});show(accepted);for(let i=0;i<65;i++){await new Promise(r=>setTimeout(r,250));const result=await api('/v1/commands/'+accepted.command_id);show(result);if(['failed','succeeded'].includes(result.status))return}throw Error('Polling timed out')});
handler('offline',async()=>disconnect());
handler('online',async()=>{if(!deviceToken)throw Error('Create a test Mac first');if(ws?.readyState===WebSocket.OPEN)return;await connect()});
handler('revoke',async()=>{if(!device)return;await api('/v1/devices/'+device.device_id,'DELETE');disconnect();device=null;deviceToken=null;$('controls').hidden=true;show('Revoked. The old device credential no longer works.');});
try{auth=await window.wandAuth.create(await(await fetch('/config')).json());const signed=await auth.isAuthenticated();$('login').hidden=signed;$('login').disabled=false;$('create').disabled=!signed;$('status').textContent=signed?'Ready. Create a test Mac to begin.':'Sign in to start your own isolated test.'}catch(e){show(e.message)}

const $=id=>document.getElementById(id);
let auth, device, deviceToken, ws, cancelConnection, locked=false;
let confirmResolve=null, confirmTrigger=null, restoreFocus=null;
function ask(title,detail,accept,trigger){
 if(confirmResolve)return Promise.resolve(false);
 $('confirm-title').textContent=title;$('confirm-detail').textContent=detail;$('confirm-accept').textContent=accept;
 confirmTrigger=trigger;
 return new Promise(resolve=>{confirmResolve=resolve;$('confirm-dialog').showModal();$('confirm-cancel').focus()});
}
function answer(accepted){
 const resolve=confirmResolve;if(!resolve)return;
 confirmResolve=null;restoreFocus=confirmTrigger;confirmTrigger=null;
 if($('confirm-dialog').open)$('confirm-dialog').close();
 resolve(accepted);
}
$('confirm-accept').onclick=()=>answer(true);
$('confirm-cancel').onclick=()=>answer(false);
$('confirm-dialog').addEventListener('cancel',event=>{event.preventDefault();answer(false)});
$('confirm-dialog').addEventListener('close',()=>{if(!$('confirm-dialog').open)answer(false)});
const show=value=>{$('output').textContent=typeof value==='string'?value:JSON.stringify(value,null,2)};
async function api(path,method='GET',data,bearer){const r=await fetch(path,{method,headers:{'Content-Type':'application/json',...(bearer===null?{}:{Authorization:'Bearer '+(bearer||await auth.getTokenSilently())})},body:data?JSON.stringify(data):undefined});const v=await r.json();if(!r.ok)throw Error(JSON.stringify(v));return v}
function capabilities(){return {schema_version:1,agent_version:'review-simulator-1',agent_build:null,os_version:'synthetic',screen_state:locked?'locked':'unlocked',actions:['get_state','lock_screen','mute','run_shortcut'],features:[],permissions:{desktop_control:'denied',accessibility:'granted',screen_recording:'denied'}}}
function send(socket,type,fields={}){socket.send(JSON.stringify({v:1,type,id:crypto.randomUUID(),ts:new Date().toISOString(),...fields}))}
function disconnect(status='Test Mac offline'){
 const socket=ws;ws=null;
 const cancel=cancelConnection;cancelConnection=null;cancel?.();
 if(socket)socket.close(1000,'reviewer_offline');
 $('status').textContent=status;
}
function revoked(){deviceToken=null;device=null;$('controls').hidden=true;disconnect('Test Mac revoked. Create a new test Mac to continue.')}
function closeMessage(code){
 if(code===4000)return 'Test Mac offline. Its heartbeat timed out; reconnect to continue.';
 if(code===4001)return 'Test Mac offline. Another connection replaced it; reconnect to continue.';
 if(code===4002)return 'Test Mac offline. The relay rejected a message; reconnect to try again.';
 return code===1000?'Test Mac offline':'Test Mac offline. The connection was interrupted; reconnect to continue.';
}
function connect(){
 if(ws)disconnect();
 return new Promise((resolve,reject)=>{
  const socket=new WebSocket('wss://app.getwand.app/review-device?device_id='+device.device_id);
  ws=socket;let heartbeat,ready=false;
  const cleanup=()=>{clearTimeout(timer);clearInterval(heartbeat)};
  const fail=message=>{
   cleanup();
   if(ws!==socket)return;
   ws=null;cancelConnection=null;
   socket.close(1000,'reviewer_connection_failed');$('status').textContent='Test Mac offline. '+message;
   reject(Error(message));
  };
  const timer=setTimeout(()=>fail('Connection timed out. Try reconnecting.'),10000);
  cancelConnection=()=>{cleanup();reject(Error('Connection cancelled. Reconnect to continue.'))};
  socket.onopen=()=>{if(ws===socket)send(socket,'hello',{device_token:deviceToken,agent_version:'review-simulator-1',device_name:'Simulated review Mac',macos_version:'synthetic',capabilities:capabilities()})};
  socket.onerror=()=>fail('The connection failed. Try reconnecting.');
  socket.onclose=event=>{
   cleanup();if(ws!==socket)return;
   ws=null;cancelConnection=null;
   if(event?.code===4003)revoked();else $('status').textContent=closeMessage(event?.code);
   if(!ready)reject(Error($('status').textContent));
  };
  socket.onmessage=event=>{
   if(ws!==socket)return;
   let m;try{m=JSON.parse(event.data)}catch{fail('The relay sent an unreadable message. Try reconnecting.');return}
   if(m.type==='ready'){
    if(ready)return;
    ready=true;clearTimeout(timer);$('status').textContent='Simulated Mac online';
    heartbeat=setInterval(()=>{if(ws!==socket)return;try{send(socket,'heartbeat',{capabilities:capabilities()})}catch{fail('The connection was interrupted. Try reconnecting.')}},25000);
    resolve();return;
   }
   if(m.type==='revoke'){revoked();return}
   if(m.type!=='command'||!ready)return;
   send(socket,'delivered',{command_id:m.command_id});let data={},error;
   if(Date.parse(m.expires_at)<Date.now()-5000)error='command_expired';
   else if(m.action==='lock_screen'){data={already_locked:locked};locked=true}
   else if(m.action==='get_state')data=locked?{screen_locked:true}:{screen_locked:false,frontmost_app:'Synthetic Finder',now_playing:null,battery:{percent:80,charging:true},running_apps:['Synthetic Finder']};
   else if(locked)error='device_locked';
   else if(m.action==='run_shortcut'&&m.params.name!=='Review Demo')error='action_not_allowlisted';
   else if(!['mute','run_shortcut'].includes(m.action))error='action_not_supported';
   send(socket,'result',{command_id:m.command_id,ok:!error,...(error?{error_code:error}:{data})});
   send(socket,'heartbeat',{capabilities:capabilities()});
  };
 });
}
function handler(id,fn){$(id).onclick=async()=>{const button=$(id);button.disabled=true;try{await fn(button)}catch(e){show(e.message)}finally{button.disabled=false;if(restoreFocus===button){restoreFocus=null;(button.closest('[hidden]')?$('create'):button).focus()}}}}
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
handler('run',async button=>{
 if(!device)throw Error('Create a test Mac first');
 let action=$('action').value;
 const params=action==='run_shortcut'?{name:'Review Demo'}:action==='reject'?{name:'Not approved'}:{};
 if(action==='reject')action='run_shortcut';
 if(action==='lock_screen'&&!await ask('Lock the simulated Mac?','Only status and lock will remain available. Revoke this test Mac to start over. Your real Mac will not lock.','Lock test Mac',button))return;
 if(action==='run_shortcut'&&!await ask(params.name==='Review Demo'?'Run the test Shortcut?':'Try an unapproved Shortcut?',params.name==='Review Demo'?'Simulate running “Review Demo”. No Shortcut runs on your real Mac.':'Send “Not approved” to check that Wand rejects a Shortcut outside the allowed list. No Shortcut runs on your real Mac.','Send test command',button))return;
 const accepted=await api('/v1/commands','POST',{device_id:device.device_id,action,params});show(accepted);
 for(let i=0;i<65;i++){await new Promise(r=>setTimeout(r,250));const result=await api('/v1/commands/'+accepted.command_id);show(result);if(['failed','succeeded'].includes(result.status))return}
 throw Error('Polling timed out');
});
handler('offline',async()=>disconnect());
handler('online',async()=>{if(!deviceToken)throw Error('Create a test Mac first');if(ws?.readyState===WebSocket.OPEN)return;await connect()});
handler('revoke',async button=>{if(!device)return;if(!await ask('Revoke this test Mac?','Disconnect the simulated Mac and invalidate its test credential. Your real Macs are unaffected.','Revoke test Mac',button))return;await api('/v1/devices/'+device.device_id,'DELETE');revoked();show('Revoked. The old device credential no longer works.');});
try{auth=await window.wandAuth.create(await(await fetch('/config')).json());const signed=await auth.isAuthenticated();$('login').hidden=signed;$('login').disabled=false;$('create').disabled=!signed;$('status').textContent=signed?'Ready. Create a test Mac to begin.':'Sign in to start your own isolated test.'}catch(e){show(e.message)}

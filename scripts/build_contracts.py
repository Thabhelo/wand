"""Generate portable JSON Schema contracts; review this source before Phase 1."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / 'contracts'
def obj(props=None, required=None):
    props = props or {}
    return {'type':'object','properties':props,'required':list(props) if required is None else required,'additionalProperties':False}
def string(maximum=160): return {'type':'string','minLength':1,'maxLength':maximum}
def enum(*values): return {'enum':list(values)}
def ref(name): return {'$ref':f'#/$defs/{name}'}
def nullable(schema): return {'anyOf':[schema,{'type':'null'}]}
UUID={'type':'string','format':'uuid'}
TIME={'type':'string','format':'date-time'}
BOOL={'type':'boolean'}
TOKEN={'type':'string','pattern':'^[A-Za-z0-9_-]{43}$'}
CODE={'type':'string','pattern':'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$'}
app=obj({'app_name':string(),'bundle_id':{'type':'string','pattern':r'^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$'}},[])
app['oneOf']=[{'required':['app_name']},{'required':['bundle_id']}]
rows=[
('lock_screen','Lock this Mac immediately, succeeding if already locked; remote unlock is impossible.','high',obj()),
('sleep_mac','Put this Mac to sleep; it may become unreachable.','medium',obj()),
('media_play_pause','Toggle playback in the active supported Music or Spotify player.','low',obj()),
('media_next','Skip to the next track in the active supported player.','low',obj()),
('media_previous','Return to the previous track in the active supported player.','low',obj()),
('set_volume','Set the system output volume from zero to one hundred.','low',obj({'level':{'type':'integer','minimum':0,'maximum':100}})),
('mute','Mute system audio output.','low',obj()),
('unmute','Unmute system audio output.','low',obj()),
('close_browser_tabs','Close tabs in the named browser after explicit confirmation, preserving pinned tabs by default.','medium',obj({'browser':enum('safari','chrome'),'keep_pinned':{'type':'boolean','default':True}},['browser'])),
('quit_app','Ask the identified app to quit gracefully after explicit confirmation.','high',app),
('open_app','Open the identified installed application.','medium',app),
('open_url','Open an HTTP or HTTPS URL in the default browser.','medium',obj({'url':{'type':'string','format':'uri','pattern':r'^https?://[^\s/]+[^\s]*(?![\s\S])','maxLength':2048}})),
('run_shortcut','Run an exactly named locally allowlisted Shortcut after confirmation.','high',obj({'name':string(200)})),
('toggle_do_not_disturb','Set Do Not Disturb to the requested enabled state.','low',obj({'enabled':BOOL})),
('get_state','Read minimal device state; a locked Mac reveals only that it is locked.','low',obj())]
catalog=[dict(name=n,description=d,risk=r,approval='always' if n=='close_browser_tabs' or r=='high' else 'never',params=p) for n,d,r,p in rows]
def actions(extra):
    return {'oneOf':[obj({**extra,'action':{'const':a['name']},'params':a['params']}) for a in catalog]}
def env(kind,props=None):
    return obj({'v':{'const':1},'type':{'const':kind},'id':UUID,'ts':TIME,**(props or {})})
D={}
D['ActionCatalog']={'type':'array','items':obj({'name':enum(*(a['name'] for a in catalog)),'description':string(500),'risk':enum('low','medium','high'),'approval':enum('never','on_high_risk','always'),'params':{'type':'object'}}),'minItems':15,'maxItems':15}
D['CommandRequest']=actions({'device_id':UUID})
D['LocalCommandRequest']=actions({})
D['HealthResponse']=obj({'status':{'const':'ok'}})
D['AccountDeletionResponse']=obj({'status':{'const':'deleted'}})
D['ErrorDetail']=obj({'code':string(80),'message':string(500),'device_id':UUID,'last_seen':nullable(TIME)},['code','message'])
D['ErrorResponse']=obj({'error':ref('ErrorDetail')})
D['Device']=obj({'device_id':UUID,'name':string(),'kind':{'const':'mac'},'online':BOOL,'last_seen':nullable(TIME)})
D['DeviceList']={'type':'array','items':ref('Device')}
D['CommandAccepted']=obj({'command_id':UUID,'status':{'const':'dispatched'}})
D['State']={'oneOf':[obj({'screen_locked':{'const':True}}),obj({'screen_locked':{'const':False},'frontmost_app':nullable(string()),'now_playing':nullable(obj({'title':string(500),'artist':string(500),'source_app':enum('Music','Spotify')})),'battery':nullable(obj({'percent':{'type':'integer','minimum':0,'maximum':100},'charging':BOOL})),'running_apps':{'type':'array','items':string(),'maxItems':512}})]}
D['LockResult']=obj({'already_locked':BOOL})
D['ActionResult']={'oneOf':[obj(),ref('State'),ref('LockResult')]}
D['CommandStatus']={'oneOf':[obj({'command_id':UUID,'status':enum('dispatched','delivered')}),obj({'command_id':UUID,'status':{'const':'succeeded'},'result':ref('ActionResult')}),obj({'command_id':UUID,'status':{'const':'failed'},'error':ref('ErrorDetail')})]}
D['PairingCodeRequest']=obj({'device_name':string(),'kind':{'const':'mac'},'agent_version':string(40)})
D['PairingCodeResponse']=obj({'device_id':UUID,'code':CODE,'bootstrap_token':TOKEN,'expires_at':TIME})
D['PairingClaimRequest']=obj({'code':CODE})
D['PairingClaimResponse']=obj({'device_id':UUID,'status':{'const':'claimed'}})
D['PairingRedeemRequest']=obj({'device_token':TOKEN})
D['PairingRedeemResponse']=obj({'device_id':UUID,'status':{'const':'paired'}})
D['RenameDeviceRequest']=obj({'name':string()})
D['RevocationResponse']=obj({'device_id':UUID,'status':{'const':'revoked'}})
D['Hello']=env('hello',{'device_token':TOKEN,'agent_version':string(40),'device_name':string(),'macos_version':string(40)})
D['PairingCancelRequest']=obj()
D['PairingCancelResponse']=obj({'status':{'const':'cancelled'}})
D['Ready']=env('ready',{'device_id':UUID})
D['PairingPreviewResponse']=obj({'device_name':string(),'expires_at':TIME})
D['Heartbeat']=env('heartbeat')
D['RevokeSelf']=env('revoke_self')
D['Delivered']=env('delivered',{'command_id':UUID})
D['Result']={'oneOf':[env('result',{'command_id':UUID,'ok':{'const':True},'data':ref('ActionResult')}),env('result',{'command_id':UUID,'ok':{'const':False},'error_code':string(80)})]}
D['Command']=actions({'v':{'const':1},'type':{'const':'command'},'id':UUID,'ts':TIME,'command_id':UUID,'expires_at':TIME})
# Reserved in v1, not an E2EE implementation. Non-null ciphertext is rejected.
for variant in D['Command']['oneOf']:
    variant['properties']['encrypted_payload']={'type':'null','description':'Reserved; non-null payloads are unsupported in v1.'}
D['Revoke']=env('revoke',{'reason':string(300)})
D['Bye']=env('bye',{'reason':string(300)})
D['DeviceMessage']={'oneOf':[ref(n) for n in ('Hello','Heartbeat','Delivered','Result','RevokeSelf','Bye')]}
D['RelayMessage']={'oneOf':[ref(n) for n in ('Command','Ready','Revoke','Bye')]}
D['AuthorizationContext']=obj({'user_id':UUID,'oauth_client_id':string(300),'allowed_actions':{'type':'array','items':enum(*(a['name'] for a in catalog)),'uniqueItems':True}})
D['LocalLogEntry']=obj({'command_id':UUID,'action':enum(*(a['name'] for a in catalog)),'params':{'type':'object'},'outcome':string(80),'created_at':TIME})
# Persisted records use the same field vocabulary as the API except explicitly documented aliases.
D['UserRow']=obj({'id':UUID,'auth_subject':string(300),'email':string(320),'created_at':TIME})
D['DeviceRow']=obj({'id':UUID,'user_id':nullable(UUID),'kind':{'const':'mac'},'name':string(),'agent_version':string(40),'online':BOOL,'last_seen_at':nullable(TIME),'created_at':TIME,'revoked_at':nullable(TIME)})
D['DeviceTokenRow']=obj({'id':UUID,'device_id':UUID,'token_hash':{'type':'string','pattern':'^[a-f0-9]{64}$'},'created_at':TIME,'revoked_at':nullable(TIME)})
D['PairingCodeRow']=obj({'code':CODE,'device_id':UUID,'bootstrap_token_hash':{'type':'string','pattern':'^[a-f0-9]{64}$'},'expires_at':TIME,'claimed_at':nullable(TIME),'redeemed_at':nullable(TIME)})
D['CommandRow']=obj({'id':UUID,'device_id':UUID,'user_id':UUID,'oauth_client_id':nullable(string(300)),'action':enum(*(a['name'] for a in catalog)),'params_json':obj({'redacted':{'const':True}}),'status':enum('dispatched','delivered','succeeded','failed'),'result_json':nullable(ref('ActionResult')),'error_json':nullable(ref('ErrorDetail')),'created_at':TIME,'expires_at':TIME})
D['AuditLogRow']=obj({'id':UUID,'user_id':UUID,'device_id':UUID,'command_id':UUID,'oauth_client_id':nullable(string(300)),'action':enum(*(a['name'] for a in catalog)),'params_json':obj({'redacted':{'const':True}}),'result_summary':string(80),'ip':nullable(string(45)),'created_at':TIME})
schema={'$schema':'https://json-schema.org/draft/2020-12/schema','$id':'https://macbridge.invalid/contracts/v1.schema.json','$defs':D}
ROOT.mkdir(exist_ok=True)
(ROOT/'v1.schema.json').write_text(json.dumps(schema,indent=2)+'\n')
(ROOT/'actions.json').write_text(json.dumps(catalog,indent=2)+'\n')

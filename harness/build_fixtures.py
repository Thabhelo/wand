"""Generate shared positive/negative examples for Python and Swift validation."""
import copy
import json
from pathlib import Path
from contracts import ACTIONS
from harness.fake_device import command, message

fixtures=[]
def add(name,model,value,valid): fixtures.append(dict(name=name,model=model,value=value,valid=valid))
params={'set_volume':{'level':50},'close_browser_tabs':{'browser':'safari'},'quit_app':{'bundle_id':'com.apple.Music'},'open_app':{'app_name':'Music'},'open_url':{'url':'https://example.com'},'run_shortcut':{'name':'My routine'},'toggle_do_not_disturb':{'enabled':True}}
for action in ACTIONS:
    name=action['name']
    add(name,'RelayMessage',command(name,params.get(name,{})),True)
    add(name+'-extra-param','RelayMessage',command(name,{**params.get(name,{}),'shell':'touch /tmp/should-never-exist'}),False)
for value in [-1,101,True,'50',0.1]: add('bad-volume-'+str(value),'RelayMessage',command('set_volume',{'level':value}),False)
for url in ['file:///etc/passwd','javascript:alert(1)','https://','https://example.com\n','https://example.com/a b']:
    add('bad-url-'+repr(url),'RelayMessage',command('open_url',{'url':url}),False)
for name in ['unlock','shell','screenshot','type_text']:
    add(name,'RelayMessage',command(name),False)
for change in [{'v':2},{'id':'bad'},{'ts':'bad'},{'extra':True},{'encrypted_payload':'ciphertext'}]:
    add('bad-envelope-'+next(iter(change)),'RelayMessage',{**command('lock_screen'),**change},False)
for value in [{'screen_locked':True},{'already_locked':True},{'already_locked':False},{}]:
    add('result-'+repr(value),'ActionResult',value,True)
add('locked-leak','ActionResult',{'screen_locked':True,'frontmost_app':'Private'},False)
add('revoke-self','DeviceMessage',message('revoke_self'),True)
add('revoke-self-wrong-direction','RelayMessage',message('revoke_self'),False)
add('revoke-self-target','DeviceMessage',message('revoke_self',device_id='1'),False)
add('scope-request-forgery','CommandRequest',{'device_id':message('x')['id'],'action':'lock_screen','params':{},'oauth_client_id':'other'},False)
for fixture in fixtures:
    # Stable fixtures make regeneration reviewable.
    for key in ['id','command_id','device_id']:
        if key in fixture['value'] and fixture['value'][key] not in ['bad','1']:
            fixture['value'][key]='11111111-1111-4111-8111-111111111111'
    for key in ['ts','expires_at']:
        if key in fixture['value'] and fixture['value'][key]!='bad': fixture['value'][key]='2026-09-20T12:00:00Z'
(Path(__file__).resolve().parents[1]/'contracts/fixtures.json').write_text(json.dumps(fixtures,indent=2)+'\n')

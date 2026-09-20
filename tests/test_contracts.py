import unittest
from uuid import uuid4
from jsonschema import ValidationError, Draft202012Validator
from contracts import ACTIONS, SCHEMA, validate

ID=str(uuid4())
TS='2026-09-20T12:00:00Z'
def command(action, params): return dict(device_id=ID,action=action,params=params)
def envelope(kind, **kwargs): return dict(v=1,type=kind,id=ID,ts=TS,**kwargs)
class ContractTests(unittest.TestCase):
    def rejects(self, model, value):
        with self.assertRaises(ValidationError): validate(model,value)
    def test_schema_and_catalog(self):
        Draft202012Validator.check_schema(SCHEMA)
        validate('ActionCatalog',ACTIONS)
        self.assertEqual(len({a['name'] for a in ACTIONS}),15)
    def test_all_valid_actions(self):
        params={'set_volume':{'level':50},'close_browser_tabs':{'browser':'safari'},'quit_app':{'bundle_id':'com.apple.Music'},'open_app':{'app_name':'Music'},'open_url':{'url':'https://example.com'},'run_shortcut':{'name':'My routine'},'toggle_do_not_disturb':{'enabled':True}}
        for action in ACTIONS:
            with self.subTest(action=action['name']): validate('CommandRequest',command(action['name'],params.get(action['name'],{})))
    def test_closed_catalog_and_no_execution_field(self):
        for action in ('unlock','shell','type_text','screenshot','delete_file'):
            self.rejects('CommandRequest',command(action,{}))
        for action in ACTIONS:
            self.rejects('CommandRequest',command(action['name'],{'shell':'touch /tmp/macbridge-injection'}))
    def test_volume_types_and_bounds(self):
        for n in (-1,101,True,'50',50.5): self.rejects('CommandRequest',command('set_volume',{'level':n}))
    def test_url_schemes(self):
        for url in ('file:///etc/passwd','javascript:alert(1)','https://','https://example.com\n','data:text/html,hello'):
            self.rejects('CommandRequest',command('open_url',{'url':url}))
    def test_app_selector_exclusive(self):
        for params in ({},{'app_name':'Music','bundle_id':'com.apple.Music'},{'bundle_id':'com.apple.Music; touch /tmp/pwn'}):
            self.rejects('CommandRequest',command('quit_app',params))
    def test_locked_state_discloses_nothing_else(self):
        validate('State',{'screen_locked':True})
        for field in ('frontmost_app','running_apps','now_playing','battery','urls','window_titles'):
            self.rejects('State',{'screen_locked':True,field:None})
    def test_confirmation_metadata(self):
        for action in ACTIONS:
            if action['risk']=='high' or action['name']=='close_browser_tabs': self.assertEqual(action['approval'],'always')
    def test_wire_directions_and_version(self):
        heartbeat=envelope('heartbeat')
        validate('DeviceMessage',heartbeat)
        self.rejects('RelayMessage',heartbeat)
        for patch in ({'v':2},{'id':'x'},{'ts':'y'},{'device_token':'leak'}): self.rejects('DeviceMessage',{**heartbeat,**patch})
    def test_result_consistency(self):
        validate('DeviceMessage',envelope('result',command_id=ID,ok=True,data={}))
        self.rejects('DeviceMessage',envelope('result',command_id=ID,ok=True,error_code='failed'))
        self.rejects('DeviceMessage',envelope('result',command_id=ID,ok=False,data={}))
    def test_pairing_code(self):
        validate('PairingClaimRequest',{'code':'ABC234'})
        for code in ('ABC012','abcdef','ABCDE','ABCDEFG'): self.rejects('PairingClaimRequest',{'code':code})
    def test_no_queue_status(self):
        self.rejects('CommandAccepted',{'command_id':ID,'status':'queued'})
    def test_reserved_encryption(self):
        c=envelope('command',command_id=ID,action='lock_screen',params={},expires_at=TS)
        validate('RelayMessage',c)
        validate('RelayMessage',{**c,'encrypted_payload':None})
        self.rejects('RelayMessage',{**c,'encrypted_payload':'ciphertext'})
    def test_terminal_results(self):
        self.rejects('CommandStatus',{'command_id':ID,'status':'succeeded'})
        self.rejects('CommandStatus',{'command_id':ID,'status':'failed','result':{}})
    def test_revoke_self_is_device_only(self):
        validate('DeviceMessage',envelope('revoke_self'))
        self.rejects('RelayMessage',envelope('revoke_self'))
        self.rejects('DeviceMessage',envelope('revoke_self',device_id=ID))
    def test_idempotent_lock_result(self):
        validate('ActionResult',{'already_locked':True})
        validate('ActionResult',{'already_locked':False})
        self.rejects('ActionResult',{'already_locked':True,'running_apps':[]})
    def test_caller_cannot_set_oauth_context(self):
        self.rejects('CommandRequest',{**command('lock_screen',{}),'oauth_client_id':'other'})
    def test_audit_params_redacted(self):
        row=dict(id=ID,user_id=ID,device_id=ID,command_id=ID,action='run_shortcut',oauth_client_id='meta-test',params_json={'redacted':True},result_summary='succeeded',ip=None,created_at=TS)
        validate('AuditLogRow',row)
        self.rejects('AuditLogRow',{**row,'params_json':{'name':'Secret routine'}})

if __name__=='__main__': unittest.main()

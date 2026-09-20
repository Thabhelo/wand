import secrets
import unittest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
from contracts import ACTIONS,validate
from relay.app import create_app,envelope
from relay.auth import Principal
from relay.store import SQLiteRepository

class TestAuth:
    async def authenticate(self, token):
        if token not in ('alice','bob'):raise ValueError()
        return Principal(token,'test-client',frozenset(a['name'] for a in ACTIONS))

class RelayTests(unittest.TestCase):
    def setUp(self):
        self.repo=SQLiteRepository(':memory:')
        self.client=TestClient(create_app(self.repo,TestAuth()))
        self.client.__enter__()
        self.headers={'Authorization':'Bearer alice'}
    def tearDown(self):self.client.__exit__(None,None,None)
    def pair(self):
        r=self.client.post('/v1/pairing/code',json={'device_name':'Test Mac','kind':'mac','agent_version':'0.3.0'})
        self.assertEqual(r.status_code,200,r.text);p=r.json();validate('PairingCodeResponse',p)
        token=secrets.token_urlsafe(32)
        redeem={'Authorization':'Bearer '+p['bootstrap_token']}
        r=self.client.post('/v1/pairing/redeem',json={'device_token':token},headers=redeem)
        self.assertEqual(r.json()['error']['code'],'pairing_pending')
        r=self.client.post('/v1/pairing/claim',json={'code':p['code']},headers=self.headers)
        self.assertEqual(r.status_code,200,r.text)
        r=self.client.post('/v1/pairing/redeem',json={'device_token':token},headers=redeem)
        self.assertEqual(r.status_code,200,r.text)
        return p,token
    def hello(self,ws,token):
        ws.send_json(envelope('hello',device_token=token,agent_version='0.3.0',device_name='Test Mac',macos_version='26.6.2'))
        ready=ws.receive_json();validate('Ready',ready)
        self.assertEqual(ready['type'],'ready')
    def test_pair_dispatch_poll_redaction_revoke(self):
        p,token=self.pair()
        with self.client.websocket_connect('/v1/ws/device') as ws:
            self.hello(ws,token)
            r=self.client.post('/v1/commands',headers=self.headers,json={'device_id':p['device_id'],'action':'open_url','params':{'url':'https://example.org/private-forensics'}})
            self.assertEqual(r.status_code,202,r.text)
            cid=r.json()['command_id'];m=ws.receive_json();validate('Command',m)
            ws.send_json(envelope('delivered',command_id=cid))
            ws.send_json(envelope('result',command_id=cid,ok=True,data={}))
            import time
            for _ in range(100):
                result=self.client.get('/v1/commands/'+cid,headers=self.headers).json()
                if result.get('status')=='succeeded':break
                time.sleep(.005)
            self.assertEqual(result['status'],'succeeded');validate('CommandStatus',result)
            self.assertNotIn('private-forensics',str(self.repo.values('commands'))+str(self.repo.values('audit')))
            r=self.client.delete('/v1/devices/'+p['device_id'],headers=self.headers)
            self.assertEqual(r.status_code,200)
            self.assertEqual(ws.receive_json()['type'],'revoke')
            with self.assertRaises(WebSocketDisconnect) as cm:ws.receive_json()
            self.assertEqual(cm.exception.code,4003)
        with self.client.websocket_connect('/v1/ws/device') as ws:
            ws.send_json(envelope('hello',device_token=token,agent_version='0.3.0',device_name='Test',macos_version='26'))
            with self.assertRaises(WebSocketDisconnect) as cm:ws.receive_json()
            self.assertEqual(cm.exception.code,4003)
    def test_offline_and_account_isolation(self):
        p,_=self.pair()
        req={'device_id':p['device_id'],'action':'lock_screen','params':{}}
        r=self.client.post('/v1/commands',headers=self.headers,json=req)
        self.assertEqual(r.status_code,409);validate('ErrorResponse',r.json())
        r=self.client.post('/v1/commands',headers={'Authorization':'Bearer bob'},json=req)
        self.assertEqual(r.status_code,404)
    def test_injection_and_closed_catalog(self):
        p,_=self.pair()
        for action,params in [('shell',{'command':'whoami'}),('open_url',{'url':'file:///etc/passwd'}),('quit_app',{'bundle_id':'com.apple.TextEdit','shell':'touch /tmp/pwn'}),('set_volume',{'level':101})]:
            r=self.client.post('/v1/commands',headers=self.headers,json={'device_id':p['device_id'],'action':action,'params':params})
            self.assertEqual(r.status_code,422,(action,r.text))
    def test_self_revoke_and_delete_cascade(self):
        p,token=self.pair()
        with self.client.websocket_connect('/v1/ws/device') as ws:
            self.hello(ws,token)
            ws.send_json(envelope('revoke_self'))
            self.assertEqual(ws.receive_json()['type'],'revoke')
        self.assertTrue(all(t['revoked_at'] for t in self.repo.values('tokens')))
        r=self.client.delete('/v1/account',headers=self.headers)
        self.assertEqual(r.status_code,200)
        validate('AccountDeletionResponse',r.json())
        for c in ('devices','tokens','pairing','commands','audit'):self.assertEqual(self.repo.values(c),[])
    def test_delete_closes_socket(self):
        p,token=self.pair()
        with self.client.websocket_connect('/v1/ws/device') as ws:
            self.hello(ws,token)
            self.assertEqual(self.client.delete('/v1/account',headers=self.headers).status_code,200)
            self.assertEqual(ws.receive_json()['type'],'revoke')
            with self.assertRaises(WebSocketDisconnect) as cm:ws.receive_json()
            self.assertEqual(cm.exception.code,4003)
    def test_auth_required_and_ui_is_real(self):
        self.assertEqual(self.client.get('/v1/devices').status_code,401)
        self.assertEqual(self.client.get('/').status_code,200)
        self.assertEqual(self.client.get('/healthz').json(),{'status':'ok'})

    def test_pairing_single_use_and_redemption_binding(self):
        p,token=self.pair()
        self.assertEqual(self.client.post('/v1/pairing/claim',headers=self.headers,json={'code':p['code']}).status_code,409)
        headers={'Authorization':'Bearer '+p['bootstrap_token']}
        self.assertEqual(self.client.post('/v1/pairing/redeem',headers=headers,json={'device_token':token}).status_code,200)
        self.assertEqual(self.client.post('/v1/pairing/redeem',headers=headers,json={'device_token':secrets.token_urlsafe(32)}).status_code,409)
        self.assertEqual(len(self.repo.values('tokens')),1)
        self.assertNotIn(token,str(self.repo.values('tokens')))
    def test_result_expiration_and_timeout(self):
        import time
        p,token=self.pair()
        with self.client.websocket_connect('/v1/ws/device') as ws:
            self.hello(ws,token)
            accepted=self.client.post('/v1/commands',headers=self.headers,json={'device_id':p['device_id'],'action':'lock_screen','params':{}}).json()
            cid=accepted['command_id'];ws.receive_json()
            c=self.repo.get('commands',cid);c['started']-=16;self.repo.put('commands',cid,c)
            ws.send_json(envelope('result',command_id=cid,ok=True,data={'already_locked':True}))
            for _ in range(100):
                result=self.client.get('/v1/commands/'+cid,headers=self.headers).json()
                if result['status']=='failed':break
                time.sleep(.005)
            self.assertEqual(result['error']['code'],'command_timeout')
    def test_disallowed_client_scope(self):
        from relay.auth import Principal
        class Restricted:
            async def authenticate(self,token):return Principal('alice','limited',frozenset({'get_state'}))
        repo=SQLiteRepository(':memory:')
        with TestClient(create_app(repo,Restricted())) as client:
            did='7d818d77-4a9a-40fd-829c-606c82214185'
            repo.put('devices',did,{'id':did,'user_id':'alice','online':False,'revoked_at':None})
            r=client.post('/v1/commands',headers=self.headers,json={'device_id':did,'action':'lock_screen','params':{}})
            self.assertEqual(r.status_code,403)
    def test_openapi_matches_routes_and_body_limit(self):
        spec=self.client.get('/openapi.json').json()
        self.assertEqual(spec['openapi'],'3.1.0')
        self.assertIn('requestBody',spec['paths']['/v1/commands']['post'])
        r=self.client.post('/v1/pairing/code',content=b'x'*65537)
        self.assertEqual(r.status_code,413)

    def test_pairing_preview_is_authenticated_and_does_not_claim(self):
        p=self.client.post('/v1/pairing/code',json={'device_name':'My Mac','kind':'mac','agent_version':'0.7.0'}).json()
        body={'code':p['code']}
        self.assertEqual(self.client.post('/v1/pairing/preview',json=body).status_code,401)
        response=self.client.post('/v1/pairing/preview',json=body,headers=self.headers)
        self.assertEqual(response.status_code,200);validate('PairingPreviewResponse',response.json())
        self.assertEqual(response.json()['device_name'],'My Mac')
        self.assertIsNone(self.repo.get('pairing',p['code'])['claimed_at'])
        self.assertEqual(self.client.post('/v1/pairing/claim',json=body,headers=self.headers).status_code,200)
        self.assertEqual(self.client.post('/v1/pairing/preview',json=body,headers=self.headers).status_code,409)

    def test_cancel_enrollment_revokes_even_after_redeem(self):
        p,token=self.pair()
        with self.client.websocket_connect('/v1/ws/device') as ws:
            self.hello(ws,token)
            r=self.client.post('/v1/pairing/cancel',headers={'Authorization':'Bearer '+p['bootstrap_token']},json={})
            self.assertEqual(r.status_code,200);validate('PairingCancelResponse',r.json())
            self.assertEqual(ws.receive_json()['type'],'revoke')
        with self.client.websocket_connect('/v1/ws/device') as ws:
            ws.send_json(envelope('hello',device_token=token,agent_version='0.7.0',device_name='Test',macos_version='26'))
            with self.assertRaises(WebSocketDisconnect) as cm:ws.receive_json()
            self.assertEqual(cm.exception.code,4003)

"""First Phase 1 component: a reusable, simulated device speaking the real contract."""
import asyncio
import json
from datetime import datetime, timezone, timedelta
from uuid import uuid4
from urllib.parse import urlsplit
from websockets.asyncio.client import connect
from websockets.exceptions import ConnectionClosed
from contracts import validate

def now(): return datetime.now(timezone.utc)
def timestamp(value=None): return (value or now()).isoformat().replace('+00:00','Z')
def message(kind, **fields): return dict(v=1,type=kind,id=str(uuid4()),ts=timestamp(),**fields)
def command(action, params=None, **fields):
    return message('command',command_id=str(uuid4()),action=action,params=params or {},expires_at=timestamp(now()+timedelta(seconds=15)),**fields)
def loopback(url):
    parsed=urlsplit(url)
    if parsed.scheme!='ws' or parsed.hostname!='127.0.0.1' or parsed.path!='/v1/ws/device' or parsed.query or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('Test peers require ws://127.0.0.1:<port>/v1/ws/device')

class FakeDevice:
    """No OS calls. Local state is intentionally isolated from the developer's Mac."""
    def __init__(self, token, *, revoke_self=False):
        self.token=token
        self.locked=True
        self.ids={}
        self.revoke_self=revoke_self
        self.revocation_pending=False

    def execute(self, request):
        current=now()
        deadline=datetime.fromisoformat(request['expires_at'].replace('Z','+00:00'))
        if (current-deadline).total_seconds()>5: return False, 'command_expired'
        if (deadline-current).total_seconds()>20: return False, 'invalid_deadline'
        self.ids={key:created for key,created in self.ids.items() if (current-created).total_seconds()<600}
        cid=request['command_id']
        if cid in self.ids: return False,'duplicate_command'
        self.ids[cid]=current
        while len(self.ids)>10000: self.ids.pop(next(iter(self.ids)))
        if self.locked:
            if request['action']=='get_state': return True, {'screen_locked':True}
            if request['action']=='lock_screen': return True, {'already_locked':True}
            return False,'device_locked'
        return False,'action_unsupported'

    async def run(self, url):
        loopback(url)
        try:
            async with connect(url,proxy=None,max_size=65536,ping_interval=None) as ws:
                async def send(value):
                    validate('DeviceMessage',value)
                    await ws.send(json.dumps(value))
                await send(message('hello',device_token=self.token,agent_version='0.1.0-probe',device_name='Simulated Mac',macos_version='26-test'))
                if self.revoke_self:
                    self.revocation_pending=True
                    await send(message('revoke_self'))
                    self.token=None
                else:
                    await send(message('heartbeat'))
                async for raw in ws:
                    request=validate('RelayMessage',json.loads(raw))
                    if request['type']=='revoke':
                        self.token=None
                        self.revocation_pending=False
                        await ws.close(code=4003)
                        return
                    if request['type']=='bye': return
                    if request['type']=='ready': continue
                    if self.revocation_pending: continue
                    ok, result=self.execute(request)
                    if ok:
                        await send(message('delivered',command_id=request['command_id']))
                    await send(message('result',command_id=request['command_id'],ok=ok,**({'data':result} if ok else {'error_code':result})))
        except ConnectionClosed as exc:
            if exc.rcvd and exc.rcvd.code==4003:
                self.token=None
                self.revocation_pending=False
            else: raise

"""Clickable loopback-only reviewer sandbox. Never loads native Mac executors.
Run: python -m harness.sandbox. Uses the real relay with isolated synthetic identities/data.
"""
import asyncio
import json
import secrets
import tempfile
from contextlib import asynccontextmanager, suppress
from pathlib import Path
import httpx
import uvicorn
from websockets.asyncio.client import connect
from fastapi.responses import HTMLResponse
from contracts import ACTIONS
from relay.app import create_app,envelope
from relay.auth import Principal
from relay.store import SQLiteRepository

PORT=8787
class SimulatorAuth:
    async def authenticate(self,token):
        if token!='simulator-only':raise ValueError('Simulator token required')
        return Principal('reviewer-simulator','simulator-only',frozenset(a['name'] for a in ACTIONS))

async def simulated_device():
    async with httpx.AsyncClient(base_url=f'http://127.0.0.1:{PORT}') as client:
        for _ in range(100):
            try:
                if (await client.get('/healthz')).is_success:break
            except httpx.ConnectError:pass
            await asyncio.sleep(.1)
        p=(await client.post('/v1/pairing/code',json={'device_name':'Simulated review Mac','kind':'mac','agent_version':'simulator-0.3.0'})).json()
        headers={'Authorization':'Bearer simulator-only'}
        await client.post('/v1/pairing/claim',headers=headers,json={'code':p['code']})
        token=secrets.token_urlsafe(32)
        await client.post('/v1/pairing/redeem',headers={'Authorization':'Bearer '+p['bootstrap_token']},json={'device_token':token})
        async with connect(f'ws://127.0.0.1:{PORT}/v1/ws/device') as ws:
            await ws.send(json.dumps(envelope('hello',device_token=token,agent_version='simulator-0.3.0',device_name='Simulated review Mac',macos_version='synthetic')))
            async def heartbeat():
                while True:
                    await ws.send(json.dumps(envelope('heartbeat')));await asyncio.sleep(25)
            task=asyncio.create_task(heartbeat());locked=False
            try:
                async for raw in ws:
                    m=json.loads(raw)
                    if m['type']=='revoke':return
                    if m['type']!='command':continue
                    cid=m['command_id'];action=m['action']
                    await ws.send(json.dumps(envelope('delivered',command_id=cid)))
                    error=None;data={}
                    if action=='lock_screen':data={'already_locked':locked};locked=True
                    elif action=='get_state':data={'screen_locked':True} if locked else dict(screen_locked=False,frontmost_app='Synthetic Finder',now_playing=None,battery={'percent':80,'charging':True},running_apps=['Synthetic Finder'])
                    elif locked:error='device_locked'
                    elif action=='run_shortcut' and m['params']['name']!='Review Demo':error='action_not_allowlisted'
                    result=envelope('result',command_id=cid,ok=error is None,**({'error_code':error} if error else {'data':data}))
                    await ws.send(json.dumps(result))
            finally:
                task.cancel()
                with suppress(asyncio.CancelledError):await task

def main():
    app=create_app(SQLiteRepository(':memory:'),SimulatorAuth())
    original=app.router.lifespan_context
    @asynccontextmanager
    async def lifespan(app):
        async with original(app):
            task=asyncio.create_task(simulated_device())
            yield
            task.cancel()
            with suppress(asyncio.CancelledError):await task
    app.router.lifespan_context=lifespan
    @app.get('/sandbox',response_class=HTMLResponse)
    async def page():return Path(__file__).with_name('sandbox.html').read_text()
    uvicorn.run(app,host='127.0.0.1',port=PORT,access_log=False,ws_max_size=65536)
if __name__=='__main__':main()

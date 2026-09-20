"""The same fake relay exercises the Python device and Swift probe over a real socket."""
import asyncio
import json
import os
from pathlib import Path
import secrets
import tempfile
import unittest
from datetime import timedelta
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
from contracts import validate
from harness.fake_device import FakeDevice, command, message, now, timestamp

ROOT=Path(__file__).resolve().parents[1]
SWIFT=os.environ.get('MACBRIDGE_SWIFT_PROBE')

class ProtocolTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self, scenario, *, swift=False, revoke_self=False, expected_failure=False):
        token=secrets.token_urlsafe(32)
        done=asyncio.get_running_loop().create_future()
        async def peer(ws):
            try:
                hello=validate('DeviceMessage',json.loads(await asyncio.wait_for(ws.recv(),5)))
                self.assertEqual(hello['type'],'hello')
                self.assertEqual(hello['device_token'],token)
                await scenario(ws)
                done.set_result(None)
            except BaseException as error:
                if not done.done(): done.set_exception(error)
        with tempfile.TemporaryDirectory(prefix='macbridge-probe-') as folder:
            async with serve(peer,'127.0.0.1',0,max_size=65536,ping_interval=None) as server:
                url=f'ws://127.0.0.1:{server.sockets[0].getsockname()[1]}/v1/ws/device'
                if swift:
                    args=[SWIFT,'--url',url,'--data-dir',folder,'--schema',str(ROOT/'contracts/v1.schema.json')]
                    if revoke_self: args.append('--revoke-self')
                    process=await asyncio.create_subprocess_exec(*args,stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,stderr=asyncio.subprocess.PIPE)
                    runner=asyncio.create_task(process.communicate((token+'\n').encode()))
                else:
                    device=FakeDevice(token,revoke_self=revoke_self)
                    runner=asyncio.create_task(device.run(url))
                try:
                    await asyncio.wait_for(done,15)
                    output=await asyncio.wait_for(runner,10)
                    if swift:
                        self.assertEqual(process.returncode,1 if expected_failure else 0,output[1].decode())
                        self.assertNotIn(token,output[0].decode()+output[1].decode())
                        if expected_failure:
                            if revoke_self:
                                state=json.loads((Path(folder)/'revocation.json').read_text())
                                self.assertTrue(state['pending'])
                            else:
                                self.assertFalse((Path(folder)/'local-log.jsonl').exists())
                        else:
                            summary=json.loads(output[0])
                            self.assertEqual(summary['token_present'],False)
                            self.assertEqual(summary['revocation_pending'],False)
                        for file in Path(folder).glob('*'):
                            self.assertNotIn(token,file.read_text())
                    else: self.assertIsNone(device.token)
                finally:
                    if swift and process.returncode is None:
                        process.kill()
                        await process.wait()
                    if not runner.done(): runner.cancel()
                    await asyncio.gather(runner,return_exceptions=True)

    async def receive(self,ws):
        while True:
            item=validate('DeviceMessage',json.loads(await asyncio.wait_for(ws.recv(),5)))
            if item['type']!='heartbeat': return item
    async def send_command(self,ws,request,expected):
        validate('RelayMessage',request)
        await ws.send(json.dumps(request))
        result=await self.receive(ws)
        if result['type']=='delivered':
            self.assertEqual(result['command_id'],request['command_id'])
            result=await self.receive(ws)
        self.assertEqual(result['type'],'result')
        self.assertEqual(result['command_id'],request['command_id'])
        for key,value in expected.items(): self.assertEqual(result[key],value)
    async def normal(self,ws):
        state=command('get_state')
        await self.send_command(ws,state,{'ok':True,'data':{'screen_locked':True}})
        await self.send_command(ws,state,{'ok':False,'error_code':'duplicate_command'})
        await self.send_command(ws,command('lock_screen'),{'ok':True,'data':{'already_locked':True}})
        await self.send_command(ws,command('open_url',{'url':'https://example.com/private?test=yes'}),{'ok':False,'error_code':'device_locked'})
        expired=command('lock_screen'); expired['expires_at']=timestamp(now()-timedelta(seconds=6))
        await self.send_command(ws,expired,{'ok':False,'error_code':'command_expired'})
        future=command('lock_screen'); future['expires_at']=timestamp(now()+timedelta(seconds=90))
        await self.send_command(ws,future,{'ok':False,'error_code':'invalid_deadline'})
        await ws.send(json.dumps(message('revoke',reason='test_complete')))
        await ws.close(code=4003)
        self.assertEqual(ws.close_code,4003)
    async def self_revoke(self,ws):
        item=await self.receive(ws)
        self.assertEqual(item['type'],'revoke_self')
        await ws.send(json.dumps(message('revoke',reason='self_revoked')))
        await ws.close(code=4003)
        self.assertEqual(ws.close_code,4003)
    async def close_only(self,ws):
        await ws.close(code=4003,reason='revoked')
    async def test_fake_device(self): await self.exercise(self.normal)
    async def test_fake_self_revoke(self): await self.exercise(self.self_revoke,revoke_self=True)
    async def test_fake_close_revocation(self): await self.exercise(self.close_only)
    @unittest.skipUnless(SWIFT,'Set MACBRIDGE_SWIFT_PROBE to run Swift integration')
    async def test_swift_device(self): await self.exercise(self.normal,swift=True)
    @unittest.skipUnless(SWIFT,'Set MACBRIDGE_SWIFT_PROBE to run Swift integration')
    async def test_swift_self_revoke(self): await self.exercise(self.self_revoke,swift=True,revoke_self=True)
    @unittest.skipUnless(SWIFT,'Set MACBRIDGE_SWIFT_PROBE to run Swift integration')
    async def test_swift_close_revocation(self): await self.exercise(self.close_only,swift=True)

    @unittest.skipUnless(SWIFT,'Set MACBRIDGE_SWIFT_PROBE to run Swift integration')
    async def test_swift_self_revoke_without_ack_stays_pending(self):
        async def no_ack(ws):
            self.assertEqual((await self.receive(ws))['type'],'revoke_self')
            await ws.wait_closed()
        await self.exercise(no_ack,swift=True,revoke_self=True,expected_failure=True)
    @unittest.skipUnless(SWIFT,'Set MACBRIDGE_SWIFT_PROBE to run Swift integration')
    async def test_swift_rejects_injected_action_before_logging(self):
        async def invalid(ws):
            await ws.send(json.dumps(command('shell',{'command':'touch /tmp/never-run'})))
            await ws.wait_closed()
        await self.exercise(invalid,swift=True,expected_failure=True)

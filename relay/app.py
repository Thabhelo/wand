import asyncio
import hashlib
import json
import logging
import os
import secrets
import time
import uuid
from collections import deque
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timezone
from pathlib import Path
from fastapi import FastAPI, Request, WebSocket
from fastapi.responses import JSONResponse, FileResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException
from jsonschema import ValidationError
from contracts import validate, SCHEMA
from relay.auth import Auth0
from relay.store import SQLiteRepository

logger=logging.getLogger('macbridge')
if not logger.handlers:
    handler=logging.StreamHandler();handler.setFormatter(logging.Formatter('%(message)s'));logger.addHandler(handler)
logger.setLevel(logging.INFO);logger.propagate=False

def stamp(t=None): return datetime.fromtimestamp(time.time() if t is None else t, timezone.utc).isoformat().replace('+00:00','Z')
def ident(): return str(uuid.uuid4())
def digest(s): return hashlib.sha256(s.encode()).hexdigest()
def envelope(kind, **fields): return dict(v=1,type=kind,id=ident(),ts=stamp(),**fields)
class Failure(Exception):
    def __init__(self, code, status=400, **extra): self.code,self.status,self.extra=code,status,extra
class Limiter:
    def __init__(self): self.items={}
    def check(self,key,limit,period):
        now=time.monotonic()
        # Bounded memory; reject new identities at capacity rather than evict active limits.
        if len(self.items)>=10000:
            self.items={k:v for k,v in self.items.items() if v and now-v[-1]<60}
            if key not in self.items and len(self.items)>=10000: raise Failure('rate_limited',429)
        q=self.items.setdefault(key,deque())
        while q and q[0]<=now-period:q.popleft()
        if len(q)>=limit:raise Failure('rate_limited',429)
        q.append(now)

def create_app(repository=None, authenticator=None):
    repo=repository or SQLiteRepository(os.getenv('DATABASE_PATH','macbridge.sqlite3'))
    auth=authenticator or Auth0()
    sockets={}; results={}; tasks=set(); limits=Limiter(); deleting=set()
    def spawn(coro):
        task=asyncio.create_task(coro);tasks.add(task);task.add_done_callback(tasks.discard)
    def save_device(d):repo.put('devices',d['id'],d)
    def audit(c, outcome):
        row=dict(id=ident(),user_id=c['user_id'],device_id=c['device_id'],command_id=c['id'],oauth_client_id=c['oauth_client_id'],action=c['action'],params_json={'redacted':True},result_summary=outcome,ip=c['ip'],created_at=stamp())
        repo.put('audit',row['id'],row)
    def finish(c,status,error=None,data=None):
        if c['status'] in ('succeeded','failed'):return
        c.update(status=status,error=error)
        repo.put('commands',c['id'],c);audit(c,error or status)
        if data is not None:results[c['id']]=(time.monotonic()+60,data)
        logger.info(json.dumps({'event':'command_finished','action':c['action'],'status':status,'latency_ms':round((time.time()-c['started'])*1000)}))
    async def revoke(d):
        d['revoked_at']=stamp();d['online']=False;save_device(d)
        for t in repo.values('tokens'):
            if t['device_id']==d['id']:t['revoked_at']=stamp();repo.put('tokens',t['token_hash'],t)
        for p in repo.values('pairing'):
            if p['device_id']==d['id']:repo.delete('pairing',p['code'])
        peer=sockets.pop(d['id'],None)
        if peer:
            with suppress(Exception):await peer['ws'].send_json(envelope('revoke',reason='device_token_revoked'))
            with suppress(Exception):await peer['ws'].close(code=4003)
        for c in repo.values('commands'):
            if c['device_id']==d['id']:finish(c,'failed','device_token_revoked')
    async def sweep():
        while True:
            await asyncio.sleep(1)
            for did,peer in list(sockets.items()):
                if time.monotonic()-peer['heartbeat']>75:
                    sockets.pop(did,None)
                    with suppress(Exception):await peer['ws'].close(code=4000)
                    d=repo.get('devices',did)
                    if d:d['online']=False;save_device(d)
            for c in repo.values('commands'):
                if c['status'] in ('dispatched','delivered') and time.time()>c['started']+15:finish(c,'failed','command_timeout')
            for cid,(expiry,_) in list(results.items()):
                if time.monotonic()>expiry:results.pop(cid,None)
            for p in repo.values('pairing'):
                if p['deadline']<time.time():
                    repo.delete('pairing',p['code'])
                    d=repo.get('devices',p['device_id'])
                    if d and not d.get('user_id'):repo.delete('devices',d['id'])
            for collection in ('audit','commands'):
                for row in repo.values(collection):
                    created=datetime.fromisoformat(row['created_at'].replace('Z','+00:00')).timestamp()
                    if created<time.time()-90*86400:repo.delete(collection,row['id'])
    @asynccontextmanager
    async def lifespan(app):
        for d in repo.values('devices'):d['online']=False;save_device(d)
        for c in repo.values('commands'):finish(c,'failed','relay_restarted')
        task=asyncio.create_task(sweep())
        yield
        task.cancel()
        for t in tasks:t.cancel()
        with suppress(asyncio.CancelledError):await task
        repo.close()
    app=FastAPI(title='MacBridge Relay',version='0.1.0',lifespan=lifespan)
    @app.exception_handler(Failure)
    async def fail(request,e):return JSONResponse({'error':{'code':e.code,'message':e.code.replace('_',' '),**e.extra}},status_code=e.status)
    @app.exception_handler(RequestValidationError)
    async def invalid(request,e):return JSONResponse({"error":{"code":"invalid_request","message":"Request does not match the API schema"}},status_code=422)
    @app.exception_handler(HTTPException)
    async def http_error(request,e):return JSONResponse({"error":{"code":"http_error","message":"Route or method unavailable"}},status_code=e.status_code)
    @app.middleware("http")
    async def bounds(request,call_next):
        if request.method in ("POST","PATCH"):
            size=0; chunks=[]
            async for chunk in request.stream():
                size+=len(chunk)
                if size>65536:return JSONResponse({"error":{"code":"request_too_large","message":"Request exceeds 64 KiB"}},status_code=413)
                chunks.append(chunk)
            request._body=b"".join(chunks)
        response=await call_next(request)
        response.headers["Cache-Control"]="no-store"
        response.headers["X-Content-Type-Options"]="nosniff"
        response.headers["Referrer-Policy"]="no-referrer"
        response.headers["X-Frame-Options"]="DENY"
        return response
    async def body(request,model):
        try:return validate(model,await request.json())
        except (ValidationError,ValueError):raise Failure('invalid_request',422)
    async def principal(request):
        header=request.headers.get('authorization','')
        if not header.startswith('Bearer '):raise Failure('unauthorized',401)
        try:
            user=await auth.authenticate(header[7:])
            if user.user_id in deleting:raise ValueError('Account deletion in progress')
            return user
        except Exception:raise Failure('unauthorized',401)
    def owned(did,user):
        d=repo.get('devices',did)
        if not d or d.get('user_id')!=user:raise Failure('device_not_found',404)
        return d
    @app.get('/healthz')
    async def health():return {'status':'ok'}
    @app.get('/')
    async def home():return FileResponse(Path(__file__).parents[1]/'web/index.html')
    @app.get('/dashboard.css')
    async def dashboard_css():return FileResponse(Path(__file__).parents[1]/'web/dashboard.css',media_type='text/css')
    @app.get('/dashboard.js')
    async def dashboard_js():return FileResponse(Path(__file__).parents[1]/'web/dashboard.js',media_type='application/javascript')
    @app.get('/mark.svg')
    async def dashboard_mark():return FileResponse(Path(__file__).parents[1]/'web/mark.svg',media_type='image/svg+xml')
    @app.get('/config')
    async def config():return {'domain':os.getenv('AUTH0_DOMAIN',''),'clientId':os.getenv('AUTH0_WEB_CLIENT_ID',''),'audience':os.getenv('AUTH0_AUDIENCE','')}
    @app.post('/v1/pairing/code')
    async def code(request:Request):
        limits.check(('enroll',request.client.host),5,60)
        b=await body(request,'PairingCodeRequest');did=ident();token=secrets.token_urlsafe(32)
        code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
        while repo.get('pairing',code):code=''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ23456789') for _ in range(6))
        save_device(dict(id=did,user_id=None,kind=b['kind'],name=b['device_name'],agent_version=b['agent_version'],online=False,last_seen=None,created_at=stamp(),revoked_at=None))
        repo.put('pairing',code,dict(code=code,device_id=did,bootstrap_token_hash=digest(token),deadline=time.time()+600,claimed_at=None,redeemed_hash=None))
        return dict(device_id=did,code=code,bootstrap_token=token,expires_at=stamp(time.time()+600))
    @app.post('/v1/pairing/preview')
    async def preview(request:Request):
        limits.check(('preview',request.client.host),5,60)
        await principal(request)
        b=await body(request,'PairingClaimRequest');p=repo.get('pairing',b['code'])
        if not p or p['deadline']<time.time() or p['claimed_at']:raise Failure('pairing_code_invalid',409)
        d=repo.get('devices',p['device_id'])
        return dict(device_name=d['name'],expires_at=stamp(p['deadline']))
    @app.post('/v1/pairing/claim')
    async def claim(request:Request):
        limits.check(('claim',request.client.host),5,60)
        user=await principal(request);b=await body(request,'PairingClaimRequest');p=repo.get('pairing',b['code'])
        if not p or p['deadline']<time.time() or p['claimed_at']:raise Failure('pairing_code_invalid',409)
        d=repo.get('devices',p['device_id']);d['user_id']=user.user_id;save_device(d)
        p['claimed_at']=stamp();repo.put('pairing',p['code'],p)
        return dict(device_id=d['id'],status='claimed')
    @app.post('/v1/pairing/cancel')
    async def cancel_enrollment(request:Request):
        limits.check(('redeem',request.client.host),60,60)
        await body(request,'PairingCancelRequest')
        raw=request.headers.get('authorization','')
        if not raw.startswith('Bearer '):raise Failure('unauthorized',401)
        p=next((p for p in repo.values('pairing') if secrets.compare_digest(p['bootstrap_token_hash'],digest(raw[7:]))),None)
        if not p:raise Failure('pairing_expired',410)
        d=repo.get('devices',p['device_id'])
        if d:await revoke(d)
        repo.delete('pairing',p['code'])
        return {'status':'cancelled'}
    @app.post('/v1/pairing/redeem')
    async def redeem(request:Request):
        limits.check(('redeem',request.client.host),60,60)
        b=await body(request,'PairingRedeemRequest');raw=request.headers.get('authorization','')
        if not raw.startswith('Bearer '):raise Failure('unauthorized',401)
        p=next((p for p in repo.values('pairing') if secrets.compare_digest(p['bootstrap_token_hash'],digest(raw[7:]))),None)
        if not p or p['deadline']<time.time():raise Failure('pairing_expired',410)
        if not p['claimed_at']:raise Failure('pairing_pending',409)
        h=digest(b['device_token']);d=repo.get('devices',p['device_id'])
        if d['revoked_at']:raise Failure('device_token_revoked',401)
        if p['redeemed_hash'] and p['redeemed_hash']!=h:raise Failure('pairing_already_redeemed',409)
        if not p['redeemed_hash']:
            repo.put('tokens',h,dict(id=ident(),device_id=d['id'],token_hash=h,created_at=stamp(),revoked_at=None))
            p['redeemed_hash']=h;repo.put('pairing',p['code'],p)
        return dict(device_id=d['id'],status='paired')
    @app.get('/v1/devices')
    async def devices(request:Request):
        u=await principal(request)
        return [dict(device_id=d['id'],name=d['name'],kind=d['kind'],online=d['id'] in sockets,last_seen=d['last_seen']) for d in repo.values('devices') if d['user_id']==u.user_id and not d['revoked_at']]
    @app.patch('/v1/devices/{did}')
    async def rename(did:str,request:Request):
        u=await principal(request);b=await body(request,'RenameDeviceRequest');d=owned(did,u.user_id);d['name']=b['name'];save_device(d)
        return dict(device_id=did,name=d['name'],kind=d['kind'],online=did in sockets,last_seen=d['last_seen'])
    @app.delete('/v1/devices/{did}')
    async def remove(did:str,request:Request):
        u=await principal(request);await revoke(owned(did,u.user_id));return dict(device_id=did,status='revoked')
    @app.delete('/v1/account')
    async def delete_account(request:Request):
        u=await principal(request)
        deleting.add(u.user_id)
        ids={d['id'] for d in repo.values('devices') if d['user_id']==u.user_id}
        for t in repo.values('tokens'):
            if t['device_id'] in ids:t['revoked_at']=stamp();repo.put('tokens',t['token_hash'],t)
        for p in repo.values('pairing'):
            if p['device_id'] in ids:repo.delete('pairing',p['code'])
        # Credentials are invalidated before the first socket-close await.
        for d in repo.values('devices'):
            if d['user_id']==u.user_id:await revoke(d)
        ids={d['id'] for d in repo.values('devices') if d['user_id']==u.user_id}
        for collection,key in [('tokens','token_hash'),('pairing','code'),('commands','id'),('audit','id'),('devices','id')]:
            for row in repo.values(collection):
                if row.get('user_id')==u.user_id or row.get('device_id') in ids:
                    if collection=='commands':results.pop(row['id'],None)
                    repo.delete(collection,row[key])
        deleting.discard(u.user_id)
        return {'status':'deleted'}
    @app.post('/v1/commands',status_code=202)
    async def commands(request:Request):
        u=await principal(request);b=await body(request,'CommandRequest');d=owned(b['device_id'],u.user_id)
        if b['action'] not in u.actions:raise Failure('action_not_authorized',403)
        limits.check(('user',u.user_id),60,60);limits.check(('device',d['id']),10,1)
        peer=sockets.get(d['id'])
        if not peer:
            rejected=dict(id=ident(),device_id=d['id'],user_id=u.user_id,oauth_client_id=u.client_id,action=b['action'],params_json={'redacted':True},status='failed',created_at=stamp(),started=time.time(),ip=request.client.host,error='device_offline')
            repo.put('commands',rejected['id'],rejected);audit(rejected,'device_offline')
            raise Failure('device_offline',409,device_id=d['id'],last_seen=d['last_seen'])
        cid=ident();c=dict(id=cid,device_id=d['id'],user_id=u.user_id,oauth_client_id=u.client_id,action=b['action'],params_json={'redacted':True},status='dispatched',created_at=stamp(),started=time.time(),ip=request.client.host,error=None,generation=peer['generation'])
        repo.put('commands',cid,c);audit(c,'dispatched')
        try:await peer['ws'].send_json(envelope('command',command_id=cid,action=b['action'],params=b['params'],expires_at=stamp(c['started']+15)))
        except Exception:finish(c,'failed','device_disconnected')
        return dict(command_id=cid,status='dispatched')
    @app.get('/v1/commands/{cid}')
    async def status(cid:str,request:Request):
        u=await principal(request);c=repo.get('commands',cid)
        if not c or c['user_id']!=u.user_id:raise Failure('command_not_found',404)
        out=dict(command_id=cid,status=c['status'])
        if c['status']=='failed':out['error']={'code':c['error'],'message':c['error'].replace('_',' ')}
        if c['status']=='succeeded':
            r=results.get(cid)
            if not r or r[0]<time.monotonic():raise Failure('result_expired',410)
            out['result']=r[1]
        return out
    @app.websocket('/v1/ws/device')
    async def device(ws:WebSocket):
        await ws.accept();did=None;peer=None
        try:
            limits.check(('hello',ws.client.host),10,60)
            h=validate('DeviceMessage',await asyncio.wait_for(ws.receive_json(),5))
            if h['type']!='hello':raise Failure('invalid_message')
            token=repo.get('tokens',digest(h['device_token']))
            if not token or token['revoked_at']:await ws.close(code=4003);return
            did=token['device_id'];d=repo.get('devices',did)
            if not d or d['revoked_at'] or d['user_id'] in deleting:await ws.close(code=4003);return
            previous=sockets.get(did)
            peer=dict(ws=ws,heartbeat=time.monotonic(),generation=ident());sockets[did]=peer
            if previous:
                for c in repo.values('commands'):
                    if c['device_id']==did and c.get('generation')==previous['generation']:finish(c,'failed','device_reconnected')
                with suppress(Exception):await previous['ws'].close(code=4001)
            d.update(online=True,last_seen=stamp(),agent_version=h['agent_version']);save_device(d)
            await ws.send_json(envelope('ready',device_id=did))
            while True:
                m=validate('DeviceMessage',await ws.receive_json())
                if sockets.get(did) is not peer or d['user_id'] in deleting:break
                if m['type']=='heartbeat':
                    peer['heartbeat']=time.monotonic();d=repo.get('devices',did);d['last_seen']=stamp();save_device(d)
                elif m['type']=='revoke_self':await revoke(repo.get('devices',did));break
                elif m['type']=='bye':break
                elif m['type'] in ('delivered','result'):
                    c=repo.get('commands',m['command_id'])
                    if not c or c.get('generation')!=peer['generation'] or c['device_id']!=did or c['status'] not in ('dispatched','delivered'):continue
                    if time.time()>c['started']+15:finish(c,'failed','command_timeout');continue
                    if m['type']=='delivered':c['status']='delivered';repo.put('commands',c['id'],c)
                    elif m['ok']:
                        data=m.get('data',{})
                        validate('AppList' if c['action']=='list_apps' else 'State' if c['action']=='get_state' else 'LockResult' if c['action']=='lock_screen' else 'ActionResult',data)
                        if c['action'] not in ('get_state','lock_screen','desktop_observe','list_apps') and data != {}:raise Failure('invalid_result')
                        finish(c,'succeeded',data=data)
                    else:finish(c,'failed',m['error_code'])
                else:raise Failure('invalid_message')
        except Exception:
            with suppress(Exception):await ws.close(code=4002)
        finally:
            if did and sockets.get(did) is peer:
                sockets.pop(did,None);d=repo.get('devices',did)
                if d:d['online']=False;save_device(d)
                for c in repo.values('commands'):
                    if c['device_id']==did:finish(c,'failed','device_disconnected')
    app.state.repository=repo
    from relay.openapi import public_spec
    app.openapi=lambda:public_spec(app)
    return app

# Use uvicorn relay.app:create_app --factory; importing modules never opens a database.

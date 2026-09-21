"""Local UI fixture. Never deploy: binds only loopback and never contacts a Mac."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,body,content_type='application/json',status=200):
        self.send_response(status);self.send_header('Content-Type',content_type);self.end_headers();self.wfile.write(body.encode() if isinstance(body,str) else body)
    def do_GET(self):
        path=self.path.split('?')[0]
        if path=='/':
            html=(ROOT/'web/index.html').read_text().replace('/firebase-auth.js','/test-auth.js').replace('We gave Muse more powers.','LOCAL TEST DATA — no Mac is controlled')
            return self.reply(html,'text/html')
        if path=='/test-auth.js':return self.reply("window.wandAuth={create:async()=>({isAuthenticated:async()=>true,getUser:async()=>({email:'tester@example.test'}),getTokenSilently:async()=>'fixture',logout:async()=>{}})};",'application/javascript')
        if path=='/config':return self.reply(json.dumps(dict(firebase=dict(apiKey='fixture',projectId='fixture'))))
        if path=='/v1/connections':return self.reply('[]')
        if path=='/v1/devices':return self.reply(json.dumps([dict(device_id='fixture-mac',name='Test MacBook',online=True,last_seen=None),dict(device_id='fixture-offline',name='Test Mac mini',online=False,last_seen='2026-09-20T12:00:00Z')]))
        if path=='/v1/commands/fixture':return self.reply(json.dumps(dict(command_id='fixture',status='succeeded',result=dict(screen_locked=False,frontmost_app='Finder',battery=dict(percent=82,charging=True),now_playing=None,running_apps=['Finder','Wand']))))
        if path in ('/dashboard.js','/dashboard.css','/mark.svg'):
            return self.reply((ROOT/'web'/path[1:]).read_bytes(),{'.js':'application/javascript','.css':'text/css','.svg':'image/svg+xml'}[Path(path).suffix])
        return self.reply('{}',status=404)
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length','0')))
        if self.path=='/v1/commands':return self.reply(json.dumps(dict(command_id='fixture',status='dispatched')),status=202)
        if self.path=='/v1/pairing/preview':return self.reply(json.dumps(dict(device_name='Test MacBook',expires_at='2099-01-01T00:00:00Z')))
        return self.reply('{}',status=404)
if __name__=='__main__':HTTPServer(('127.0.0.1',8792),Handler).serve_forever()

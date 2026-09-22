"""Read-only loopback prompt page. It cannot send input or approve acceptance."""
import argparse
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import time
import uuid
import human_build  # Establish the existing acceptance helper path.
from acceptance_common import require
import s2_hosting_workflow as shared


PAGE=b'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>S2 acceptance</title>
<style>body{font:18px system-ui;margin:32px auto;max-width:900px;padding:0 24px;background:#f7f8fa;color:#17212b}h1{font-size:28px}#context,#clock{color:#506070}#instruction{font-size:24px;line-height:1.4}img{max-width:100%;max-height:65vh;object-fit:contain;background:white;border:1px solid #ddd}p{line-height:1.5}</style>
<h1>S2 acceptance</h1><p>Perform each requested gesture once in Device Hub, then wait. Native evidence advances the run automatically.</p><p id="context"></p><p id="instruction">Waiting for a ready step.</p><p id="clock"></p><img id="image" hidden alt="Actual ready app screenshot">
<script>
let generation=null,current=null;const instruction=document.getElementById('instruction'),context=document.getElementById('context'),clock=document.getElementById('clock'),image=document.getElementById('image');
function live(state){return !!state&&state.ready&&state.deadline>Date.now()/1000;}
async function refresh(){try{const response=await fetch('/state',{cache:'no-store'});if(!response.ok)throw Error('state unavailable');const state=await response.json();current=state;context.textContent=state.context||'';const left=state.deadline?Math.ceil(state.deadline-Date.now()/1000):null;const expired=left!==null&&left<=0;instruction.textContent=expired?'Input window closed. Wait for the next ready step.':state.instruction;clock.textContent=expired?'':left===null?'':left+' seconds remaining';if(generation!==state.generation){generation=state.generation;image.hidden=true;image.onload=null;image.removeAttribute('src');if(state.has_image&&live(state)){const requested=state.generation;image.onload=()=>{image.hidden=!(generation===requested&&current.generation===requested&&live(current));};image.src='/image?generation='+encodeURIComponent(requested);}}if(!live(state))image.hidden=true;}catch(error){current=null;generation=null;instruction.textContent='Prompt page unavailable. Wait; do not repeat a gesture.';clock.textContent='';image.hidden=true;image.onload=null;}finally{setTimeout(refresh,500);}}refresh();
</script></html>'''


def publish(directory,payload,*,context='',ready=False,cleanup=False):
    directory=Path(directory).resolve();require(directory.is_dir(),'operator output not preflighted')
    require(isinstance(payload.get('instruction'),str) and payload['instruction'],'missing human instruction')
    if ready:require(type(payload.get('deadline')) in [int,float] and time.time()<payload['deadline'],'expired or missing human prompt clock')
    record={'schema_version':1,'generation':str(uuid.uuid4()),'published_at':time.time(),'context':context,
        'instruction':payload['instruction'] if ready else payload.get('instruction','Capturing evidence. Wait for the next ready step.'),
        'deadline':payload.get('deadline') if ready else None,'has_image':False,'ready':ready,'cleanup_started':cleanup}
    if ready and payload.get('screenshot'):
        path=image_path(directory,payload['screenshot'])
        raw=path.read_bytes();require(raw.startswith(b'\x89PNG\r\n\x1a\n'),'operator image is not actual PNG')
        if 'screenshot_sha256' in payload:require(hashlib.sha256(raw).hexdigest()==payload['screenshot_sha256'],'actual returned screenshot changed')
        record.update(has_image=True,image_path=str(path),image_sha256=hashlib.sha256(raw).hexdigest())
    shared.save(directory/'state.json',record)
    return record


def forward(directory,message,*,context):
    cleanup=shared.read(Path(directory)/'state.json').get('cleanup_started') is True
    if 'cell_phase' in message:
        publish(directory,{'instruction':'Cleanup in progress. Do not interact unless a separate restoration prompt appears.'},context=context,cleanup=True)
    elif 'human_input' in message:
        prompt=message['human_input']
        require(not cleanup or prompt.get('kind')=='cleanup','ordinary input after cleanup is forbidden')
        publish(directory,prompt,context=context,ready=True,cleanup=cleanup)
    elif 'human_status' in message:publish(directory,message['human_status'],context=context,cleanup=cleanup)


def image_path(directory,value):
    path=Path(value);base=directory.parent/'cells'
    require(path.is_absolute() and path.is_relative_to(base) and path.resolve().is_relative_to(base)
            and path.is_file() and not any(p.is_symlink() for p in [path,*path.parents]),'foreign/symlinked operator image')
    return path


def image_bytes(directory,generation):
    directory=Path(directory).resolve();state=shared.read(directory/'state.json')
    require(state.get('generation')==generation and state.get('ready') is True and state.get('has_image') is True
            and time.time()<state['deadline'],'stale or expired operator image')
    path=image_path(directory,state['image_path'])
    raw=path.read_bytes();require(hashlib.sha256(raw).hexdigest()==state['image_sha256'],'operator image changed');return raw


def serve(args):
    directory=args.directory.resolve();require(directory.is_dir() and args.seconds>0 and args.seconds<=21600,'unbounded or unprepared operator page')
    deadline=time.monotonic()+args.seconds
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def respond(self,status,body,kind):
            self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(body)))
            self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff')
            self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'")
            self.end_headers();self.wfile.write(body)
        def do_GET(self):
            try:
                require(self.client_address[0]=='127.0.0.1','nonlocal operator request')
                if self.path=='/':return self.respond(200,PAGE,'text/html; charset=utf-8')
                if self.path=='/state':
                    state=shared.read(directory/'state.json');state.pop('image_path',None);return self.respond(200,json.dumps(state).encode(),'application/json')
                if self.path.startswith('/image?generation='):
                    identifier=self.path.split('=',1)[1];require(str(uuid.UUID(identifier))==identifier,'invalid image generation')
                    return self.respond(200,image_bytes(directory,identifier),'image/png')
                self.respond(404,b'Not found','text/plain')
            except (BrokenPipeError,ConnectionResetError):return
            except Exception:self.respond(409,b'Current evidence is unavailable','text/plain')
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.timeout=.5
    receipt={'state':'READ_ONLY_OPERATOR_PAGE','pid':__import__('os').getpid(),'url':'http://127.0.0.1:'+str(server.server_port),
        'started_at':time.time(),'seconds':args.seconds,'native_launches':0}
    shared.save(directory/'server.json',receipt,exclusive=True);print(json.dumps(receipt),flush=True)
    try:
        while time.monotonic()<deadline:server.handle_request()
    finally:server.server_close()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--directory',type=Path,required=True);parser.add_argument('--seconds',type=int,default=14400)
    serve(parser.parse_args())
if __name__=='__main__':main()

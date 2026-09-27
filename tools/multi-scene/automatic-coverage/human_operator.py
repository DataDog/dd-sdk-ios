"""Loopback prompts and bound release acknowledgements; no native input or acceptance."""
import argparse
import contextlib
import fcntl
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import time
import uuid
import urllib.request
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'acceptance'))
from acceptance_common import require
import s2_hosting_workflow as shared


PAGE=b'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>S2 acceptance</title>
<style>body{font:18px system-ui;margin:32px auto;max-width:900px;padding:0 24px;background:#f7f8fa;color:#17212b}h1{font-size:28px}#context,#clock{color:#506070}#instruction{font-size:24px;line-height:1.4}img{max-width:100%;max-height:65vh;object-fit:contain;background:white;border:1px solid #ddd}p{line-height:1.5}</style>
<h1>RUM acceptance</h1><p>Perform each requested gesture once, then wait. Native evidence advances the run automatically.</p><p id="context"></p><p id="instruction">Waiting for a ready step.</p><p id="clock"></p><button id="released" hidden>Released</button><img id="image" hidden alt="Actual ready app screenshot">
<script>
let generation=null,current=null;const instruction=document.getElementById('instruction'),context=document.getElementById('context'),clock=document.getElementById('clock'),image=document.getElementById('image');
const released=document.getElementById('released');
released.onclick=async()=>{const submitted=current.generation;released.disabled=true;try{const response=await fetch('/released',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({generation:submitted})});if(!response.ok)throw Error('acknowledgement rejected');}catch(error){if(current&&current.generation===submitted)instruction.textContent='Release acknowledgement was not recorded. Keep input released; wait for assistance.';}finally{if(current&&current.generation===submitted)released.hidden=true;}};
function live(state){return !!state&&state.ready&&state.deadline>Date.now()/1000;}
async function refresh(){
  try{
    const response=await fetch('/state',{cache:'no-store'});if(!response.ok)throw Error('state unavailable');
    const state=await response.json();current=state;context.textContent=state.context||'';
    const expired=state.deadline&&state.deadline<=Date.now()/1000;
    instruction.textContent=expired?'Input window closed. Keep input released; wait for assistance.':state.instruction;
    clock.textContent='';
    if(generation!==state.generation){
      generation=state.generation;image.hidden=true;image.onload=null;image.removeAttribute('src');
      released.hidden=!(live(state)&&state.release_label);released.disabled=false;released.textContent=state.release_label||'Released';
      if(state.has_image&&live(state)){
        const requested=state.generation;
        image.onload=()=>{image.hidden=!(generation===requested&&current&&current.generation===requested&&live(current));};
        image.src='/image?generation='+encodeURIComponent(requested);
      }
    }
    if(!live(state)){image.hidden=true;released.hidden=true;}
  }catch(error){
    current=null;generation=null;instruction.textContent='Prompt page unavailable. Wait; do not repeat a gesture.';
    clock.textContent='';image.hidden=true;image.onload=null;released.hidden=true;
  }finally{setTimeout(refresh,500);}
}refresh();
</script></html>'''


@contextlib.contextmanager
def publication_lock(directory):
    # The runner and HTTP server are different processes. Serialize publication
    # and acknowledgement so a click cannot retire a newer request.
    with (Path(directory)/'.publication.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX)
        try:yield
        finally:fcntl.flock(lock,fcntl.LOCK_UN)


def publish(directory,payload,**kwargs):
    with publication_lock(directory):return _publish(directory,payload,**kwargs)


def _publish(directory,payload,*,context='',ready=False,cleanup=False):
    directory=Path(directory).resolve();require(directory.is_dir(),'operator output not preflighted')
    require(isinstance(payload.get('instruction'),str) and payload['instruction'],'missing human instruction')
    if ready:require(type(payload.get('deadline')) in [int,float] and time.time()<payload['deadline'],'expired or missing human prompt clock')
    record={'schema_version':1,'generation':str(uuid.uuid4()),'published_at':time.time(),'context':context,
        'instruction':payload['instruction'] if ready else payload.get('instruction','Capturing evidence. Wait for the next ready step.'),
        'deadline':payload.get('deadline') if ready else None,'has_image':False,'ready':ready,'cleanup_started':cleanup}
    if ready and payload.get('request_path'):
        source=Path(payload['request_path']);path=source.resolve();base=directory.parent/'cells'
        require(source.is_absolute() and path.is_relative_to(base) and path.is_file()
            and not any(p.is_symlink() for p in [source,*source.parents]),'foreign release request')
        request=shared.read(path)
        require(request['kind']=='HUMAN_RELEASE_REQUIRED' and request['request_id']==payload['request_id']
            and request['run_id']==payload['run_id'] and request['deadline']==payload['deadline'],'release request differs')
        record.update(release_request=str(path),release_sha256=shared.sha(path),release_label='Ready' if payload.get('phase')=='setup' else 'Released')
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
    elif 'human_release' in message or 'human_setup' in message:
        payload=message.get('human_release',message.get('human_setup'))
        publish(directory,payload,context=context,ready=True,cleanup=payload.get('phase')!='setup')
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


def acknowledge(directory,generation):
    with publication_lock(directory):return _acknowledge(directory,generation)


def _acknowledge(directory,generation):
    state=shared.read(directory/'state.json');now=time.time()
    require(state['generation']==generation and state['ready'] and now<state['deadline'],'stale release page')
    path=Path(state['release_request']);raw=path.read_bytes();request=json.loads(raw)
    require(shared.sha(path)==state['release_sha256'] and request['issued_at']<=now<request['deadline'],'release request changed')
    reply=dict(kind='OPERATOR_RELEASED',request_sha256=state['release_sha256'],request_id=request['request_id'],
        run_id=request['run_id'],at=now,user_message='Operator clicked '+state['release_label']+' on the bound local prompt page')
    shared.save(path.with_name('operator-released.json'),reply,exclusive=True)
    _publish(directory,{'instruction':'Release recorded. Waiting for native idle evidence; do not interact.'},context=state['context'],cleanup=state['cleanup_started'])


def ready(directory,receipt,plan_path,*,device,mode):
    """Verify a live local page and explicit, fresh readiness before native work."""
    directory=Path(directory).resolve();server=shared.read(directory/'server.json');now=time.time()
    require(receipt.get('kind')=='OPERATOR_READY' and receipt.get('plan_sha256')==shared.sha(plan_path)
        and receipt.get('channel')==server and receipt.get('device')==device and receipt.get('mode')==mode
        and receipt.get('user_message_reference') and 0<=now-receipt['at']<=300,'fresh bound operator readiness required')
    require(server['url'].startswith('http://127.0.0.1:') and server['directory']==str(directory)
        and now<server['started_at']+server['seconds'],'operator page expired or foreign')
    with urllib.request.urlopen(server['url']+'/health',timeout=2) as response:actual=json.load(response)
    require(actual==server,'operator page process/nonce changed')
    return server


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
                if self.path=='/health':return self.respond(200,json.dumps(receipt).encode(),'application/json')
                if self.path=='/state':
                    state=shared.read(directory/'state.json');state.pop('image_path',None);state.pop('release_request',None);return self.respond(200,json.dumps(state).encode(),'application/json')
                if self.path.startswith('/image?generation='):
                    identifier=self.path.split('=',1)[1];require(str(uuid.UUID(identifier))==identifier,'invalid image generation')
                    return self.respond(200,image_bytes(directory,identifier),'image/png')
                self.respond(404,b'Not found','text/plain')
            except (BrokenPipeError,ConnectionResetError):return
            except Exception:self.respond(409,b'Current evidence is unavailable','text/plain')
        def do_POST(self):
            try:
                origin='http://127.0.0.1:'+str(server.server_port)
                require(self.client_address[0]=='127.0.0.1' and self.path=='/released'
                    and self.headers.get('Origin')==origin and self.headers.get('Host')==origin.removeprefix('http://')
                    and self.headers.get('Content-Type')=='application/json','foreign release publication')
                count=int(self.headers['Content-Length']);require(0<count<=256,'invalid release body')
                payload=json.loads(self.rfile.read(count));require(set(payload)=={'generation'},'invalid release fields')
                acknowledge(directory,payload['generation']);self.respond(200,b'{}','application/json')
            except Exception:self.respond(409,b'Release was not recorded','text/plain')
    server=ThreadingHTTPServer(('127.0.0.1',0),Handler);server.timeout=.5
    receipt={'state':'BOUND_OPERATOR_PAGE','pid':__import__('os').getpid(),'url':'http://127.0.0.1:'+str(server.server_port),
        'started_at':time.time(),'seconds':args.seconds,'native_launches':0,'directory':str(directory),'nonce':str(uuid.uuid4())}
    shared.save(directory/'server.json',receipt,exclusive=True);print(json.dumps(receipt),flush=True)
    try:
        while time.monotonic()<deadline:server.handle_request()
    finally:server.server_close()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--directory',type=Path,required=True);parser.add_argument('--seconds',type=int,default=14400)
    serve(parser.parse_args())
if __name__=='__main__':main()

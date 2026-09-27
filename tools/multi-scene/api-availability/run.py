#!/usr/bin/env python3
"""One finite optimized client cell with local intake, evidence and task-app cleanup."""
import argparse
import gzip
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import re
import threading
import time
import urllib.request
import urllib.parse
import uuid
import zlib
import build
import contract

shared=build.shared


def run(root, udid, os_version, mode, attempt=None, *, qualification=None, human_setup=False,
        human_verify=None, prompt_channel=None, output_root=None):
    contract.require(type(human_setup) is bool and (not human_setup or qualification is not None), 'invalid human setup mode')
    if human_setup:
        import same_key_human as human_preparation
        verify_human=human_verify or (lambda:human_preparation.verify(root))
        verify_human()
    plan=build.verify(root); built=shared.read(root/'simulator/product.json')
    app=Path(built['path']); contract.require(shared.product(app,build.BUNDLE)==built['product'],'changed product')
    cells=(output_root or root)/'cells'; cells.mkdir(exist_ok=True)
    contract.require(attempt is None or re.fullmatch(r'[a-z0-9][a-z0-9-]{0,31}',attempt), 'invalid attempt label')
    folder=cells/(os_version+'-'+mode+('-'+attempt if attempt else '')); folder.mkdir()
    run_id=str(uuid.uuid4()); started=time.time(); deadline=started+(1800 if human_setup else 300)
    summary=dict(attempt=attempt,run_id=run_id,source=plan['source'],device=udid,runtime=os_version,automatic=mode,started_at=started,
                 execution_deadline=deadline,scenario='NOT_EXECUTED',evidence='INCOMPLETE',cleanup='NOT_STARTED',overall='INVALID')
    if human_setup:
        summary.update(setup_deadline=deadline, execution_deadline=None, input_mode='human-same-key-setup')
    helpers={n:shared.sha(Path(__file__).parent/n) for n in ['build.py','run.py','contract.py']}
    checkpoints=[]; launch_published=threading.Event()
    if qualification is not None:
        contract.require(plan.get('multiple_scenes') is True and mode in ['swift','objc'], 'incorrect same-key admission')
        for name in ['same_key.py','same_key_contract.py']:
            helpers[name]=shared.sha(Path(__file__).parent/name)
    if human_setup:
        import same_key_setup
        for name in ['same_key_setup.py', '../interactive-transitions/physical_release.py', '../app-acceptance/capture_io.py']:
            helpers[name]=shared.sha(Path(__file__).parent/name)
    shared.save(folder/'admission.json',dict(**summary,helpers=helpers,product_sha256=shared.sha(root/'simulator/product.json')),exclusive=True)
    events=[]; http_errors=[]; lock=threading.Lock(); requests_count=0; sealed=False; boundary=None
    request_threads=[]; thread_lock=threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args): pass
        def do_GET(self):
            nonlocal boundary
            url=urllib.parse.urlparse(self.path)
            if url.path=='/boundary':
                with lock:
                    valid=not sealed and boundary is None and urllib.parse.parse_qs(url.query).get('run_id')==[run_id]
                    if valid:
                        boundary=dict(run_id=run_id,nonce=str(uuid.uuid4()),event_count=len(events),at=time.time())
                        shared.save(folder/'pre-background.json',dict(receipt=boundary,events=list(events)),exclusive=True)
                        body=json.dumps(boundary).encode()
                    else: body=b'{}';http_errors.append('invalid or duplicate boundary request')
                self.send_response(200 if valid else 409);self.send_header('Content-Length',str(len(body)));self.end_headers();self.wfile.write(body)
            else:
                self.send_response(200 if self.path=='/health' else 404); self.end_headers()
        def do_POST(self):
            nonlocal requests_count
            body=self.rfile.read(int(self.headers['Content-Length']))
            if self.path == '/checkpoint' and qualification is not None:
                if not launch_published.wait(timeout=10):
                    http_errors.append('launch identity not published before checkpoint')
                with lock:
                    stem='checkpoint-'+str(len(checkpoints))
                    (folder/(stem+'.bin')).write_bytes(body)
                    native=None; accepted=None
                    try:
                        contract.require(not sealed and time.time()<deadline, 'late checkpoint')
                        native=json.loads(body)
                        qualification.validate_envelope(native,run_id,plan['source'],mode,pid,os_version)
                        if human_setup:
                            contract.require(barrier is not None, 'human setup identity unavailable')
                            barrier.validate(native)
                        accepted=qualification.validate_checkpoint(native,list(events),checkpoints)
                        ack=dict(run_id=run_id,phase=native['phase'],nonce=str(uuid.uuid4()),event_count=len(events),at=time.time())
                        checkpoints.append(dict(native=native,events=list(events),ack=ack,assertions=accepted))
                        shared.save(folder/(stem+'.json'),checkpoints[-1],exclusive=True)
                        status=200
                    except Exception as error:
                        http_errors.append('checkpoint rejected: '+str(error));status=409
                        ack=dict(failure=str(error))
                        shared.save(folder/(stem+'-rejected.json'),dict(native=native,events=list(events),failure=str(error)),exclusive=True)
                    encoded=json.dumps(ack).encode()
                self.send_response(status);self.send_header('Content-Length',str(len(encoded)));self.end_headers();self.wfile.write(encoded)
                return
            encoding=self.headers.get('Content-Encoding','identity')
            with lock:
                if sealed: http_errors.append('request after seal')
                requests_count+=1; stem='intake-'+str(requests_count)
                (folder/(stem+'.bin')).write_bytes(body)
                shared.save(folder/(stem+'.json'),dict(at=time.time(),encoding=encoding,bytes=len(body)),exclusive=True)
                try:
                    if encoding=='gzip': decoded=gzip.decompress(body)
                    elif encoding=='deflate': decoded=zlib.decompress(body)
                    elif encoding=='identity': decoded=body
                    else: raise ValueError('unsupported content encoding')
                    (folder/(stem+'.jsonl')).write_bytes(decoded)
                    rows=[json.loads(line) for line in decoded.splitlines() if line]
                    contract.require(all(isinstance(row,dict) for row in rows),'invalid intake record')
                    events.extend(rows)
                except Exception as error: http_errors.append(type(error).__name__+': '+str(error))
            self.send_response(202); self.end_headers()

    class Server(ThreadingHTTPServer):
        daemon_threads=False
        def get_request(self):
            request,address=super().get_request();request.settimeout(10);return request,address
        def process_request_thread(self,request,address):
            with thread_lock:request_threads.append(threading.current_thread())
            super().process_request_thread(request,address)
    server=Server(('127.0.0.1',0),Handler)
    worker=threading.Thread(target=server.serve_forever);worker.start()
    port=server.server_port
    installed=False; stopped=False; pid=None; location=None; container=None; server_closed=False
    barrier=None; human_idle=False; release_attempted=False; cleanup_deadline=None; launch_attempted=False
    def admit_api(record):
        nonlocal deadline
        verify_human()
        contract.require(human_setup and summary['execution_deadline'] is None and time.time()<summary['setup_deadline'],
                         'human API admission is consumed or late')
        deadline=record['execution_deadline']
        summary.update(execution_started_at=record['started_at'], execution_deadline=deadline)
    sequence=0
    def command(args, *, check=True, limit=None):
        nonlocal sequence
        sequence+=1; remaining=(limit if limit is not None else deadline)-time.time()
        contract.require(remaining>0,'command after fixed deadline')
        result=shared.capture(args,timeout=min(remaining,60),check=False)
        (folder/('command-'+str(sequence)+'.stdout')).write_bytes(result.stdout)
        (folder/('command-'+str(sequence)+'.stderr')).write_bytes(result.stderr)
        shared.save(folder/('command-'+str(sequence)+'.json'),dict(argv=args,returncode=result.returncode,finished_at=time.time()),exclusive=True)
        contract.require(not check or result.returncode==0,'command failed: '+args[1])
        return result
    def prove_absence(limit):
        result=command(['ps','-axo','pid=,command='],limit=limit)
        rows=result.stdout.decode().splitlines()
        matching=[]
        for row in rows:
            parts=row.strip().split(None,1)
            if not parts:continue
            if (pid is not None and int(parts[0])==pid) or (location is not None and str(location/'APIClient') in row): matching.append(row)
        contract.require(not matching,'task PID/executable still present')
    def close_server(limit):
        nonlocal server_closed
        if server_closed:return
        server.shutdown();worker.join(timeout=min(5,max(0,limit-time.time())))
        with thread_lock:threads=list(request_threads)
        for thread in threads:thread.join(timeout=min(10,max(0,limit-time.time())))
        contract.require(not worker.is_alive() and all(not t.is_alive() for t in threads),'HTTP workers not quiescent')
        server.server_close();server_closed=True
        shared.save(folder/'http-quiescence.json',dict(threads=len(threads),alive=0,at=time.time()),exclusive=True)
    try:
        with urllib.request.urlopen('http://127.0.0.1:'+str(port)+'/health',timeout=5) as response:
            contract.require(response.status==200,'response publication unavailable')
        state=json.loads(command(['xcrun','simctl','list','devices','available','--json']).stdout)
        found=[(runtime,d) for runtime,ds in state['devices'].items() for d in ds if d['udid']==udid]
        contract.require(len(found)==1 and os_version.replace('.','-') in found[0][0],'wrong simulator runtime')
        summary['initial_state']=found[0][1]['state']
        if summary['initial_state']=='Shutdown':
            command(['xcrun','simctl','boot',udid]);command(['xcrun','simctl','bootstatus',udid,'-b'])
        absent=command(['xcrun','simctl','get_app_container',udid,build.BUNDLE,'data'],check=False)
        contract.require(absent.returncode!=0 and b'No such file' in absent.stderr,'clean install not proved')
        command(['xcrun','simctl','install',udid,str(app)]);installed=True
        location=Path(command(['xcrun','simctl','get_app_container',udid,build.BUNDLE,'app']).stdout.decode().strip())
        installed_product=shared.product(location,build.BUNDLE)
        shared.save(folder/'installed.json',dict(path=str(location),product=installed_product),exclusive=True)
        contract.require(installed_product==built['product'],'installed code differs')
        container=Path(command(['xcrun','simctl','get_app_container',udid,build.BUNDLE,'data']).stdout.decode().strip())
        output=container/'Documents/result.json';contract.require(not output.exists(),'stale fixture output')
        launch_attempted=True
        launched=command(['xcrun','simctl','launch',udid,build.BUNDLE,'--run-id',run_id,'--endpoint','http://127.0.0.1:'+str(port)+'/rum',('--language' if qualification is not None else '--automatic'),mode]+(['--human-setup'] if human_setup else []))
        match=re.fullmatch(re.escape(build.BUNDLE)+r': (\d+)\s*',launched.stdout.decode());contract.require(match,'launch PID missing')
        pid=int(match[1]);summary['pid']=pid;launch_published.set()
        if human_setup:
            barrier=same_key_setup.Barrier(folder, container/'Documents',
                dict(run_id=run_id, source=plan['source'], pid=pid), summary['setup_deadline'], prompt_channel=prompt_channel)
        while not output.exists():
            if human_setup:barrier.poll(admit_api)
            contract.require(time.time()<deadline,'result receipt deadline expired')
            time.sleep(.2)
        (folder/'result.json').write_bytes(output.read_bytes())
        receipt=shared.read(folder/'result.json')
        contract.require(time.time()<deadline,'late native result')
        terminal_limit=deadline
        if human_setup:
            barrier.validate(receipt)
            summary['api_finished_at']=time.time()
            cleanup_deadline=time.time()+300; terminal_limit=cleanup_deadline
            release_attempted=True;barrier.cleanup(cleanup_deadline);human_idle=True
        command(['xcrun','simctl','terminate',udid,build.BUNDLE],limit=terminal_limit);stopped=True
        prove_absence(terminal_limit)
        close_server(terminal_limit)
        with lock:
            sealed=True;captured=list(events);errors=list(http_errors)
        shared.save(folder/'events.json',captured,exclusive=True);shared.save(folder/'intake-errors.json',errors,exclusive=True)
        contract.require(not errors,'intake decoding failed')
        if qualification is None:
            contract.require(receipt.get('pre_background')==boundary and boundary is not None,'unbound background boundary')
        summary['evidence']='PASS'
        if qualification is None:
            summary['assertions']=contract.validate(receipt,captured,run_id,plan['source'],mode,pid,os_version)
        else:
            summary['assertions']=qualification.validate(receipt,captured,checkpoints,run_id,plan['source'],mode,pid,os_version)
        summary['scenario']='PASS'
        contract.require(time.time()<terminal_limit,'late final assertion')
    except Exception as error:
        summary['failure']=type(error).__name__+': '+str(error)
        summary['scenario']='ASSERTION_OR_HARNESS_FAILURE'
    finally:
        summary['execution_finished_at']=time.time()
        if cleanup_deadline is None:cleanup_deadline=time.time()+(300 if human_setup else 180)
        summary['cleanup_deadline']=cleanup_deadline
        try:
            if installed:
                if human_setup and launch_attempted and not human_idle:
                    contract.require(barrier is not None and not release_attempted,
                                     'human release/native idle unproved; preserve task app')
                    release_attempted=True;barrier.cleanup(cleanup_deadline);human_idle=True
                if not stopped:command(['xcrun','simctl','terminate',udid,build.BUNDLE],check=False,limit=cleanup_deadline)
                prove_absence(cleanup_deadline)
                command(['xcrun','simctl','uninstall',udid,build.BUNDLE],limit=cleanup_deadline)
                # Uninstall acknowledgement can precede durable simulator state.
                for _ in range(3):
                    for kind in ['app','data']:
                        absent=command(['xcrun','simctl','get_app_container',udid,build.BUNDLE,kind],check=False,limit=cleanup_deadline)
                        contract.require(absent.returncode!=0 and b'No such file' in absent.stderr,'task container remains')
                    contract.require(not location.exists() and not container.exists(),'task files remain after uninstall')
                    contract.require(time.time()+2<cleanup_deadline,'cleanup settlement exceeds deadline')
                    time.sleep(2)
            if summary.get('initial_state')=='Shutdown': command(['xcrun','simctl','shutdown',udid],limit=cleanup_deadline)
            state=json.loads(command(['xcrun','simctl','list','devices','available','--json'],limit=cleanup_deadline).stdout)
            after=[d['state'] for ds in state['devices'].values() for d in ds if d['udid']==udid]
            contract.require(after==[summary.get('initial_state')],'simulator state not restored')
            contract.require(build.protected()==plan['protected'],'protected workspace changed')
            contract.require({n:shared.sha(Path(__file__).parent/n) for n in helpers}==helpers,'runner/oracle changed during cell')
            build.verify(root)
            if human_setup:verify_human()
            close_server(cleanup_deadline)
            summary['cleanup']='PASS'
        except Exception as error: summary['cleanup']='FAILED';summary['cleanup_failure']=type(error).__name__+': '+str(error)
        if not server_closed:
            try:close_server(cleanup_deadline)
            except Exception as error:summary['cleanup']='FAILED';summary['http_cleanup_failure']=str(error)
        summary['finished_at']=time.time()
        if all(summary[k]=='PASS' for k in ['scenario','evidence','cleanup']):summary['overall']='PASS'
        shared.save(folder/'summary.json',summary,exclusive=True)
    print(json.dumps({k:summary[k] for k in ['run_id','scenario','evidence','cleanup','overall']}),flush=True)
    return summary['overall']=='PASS'


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--device',required=True)
    parser.add_argument('--os',required=True);parser.add_argument('--automatic',choices=['on','off'],required=True)
    parser.add_argument('--attempt',help='Separately admitted continuation label; never overwrites an earlier cell')
    args=parser.parse_args()
    raise SystemExit(0 if run(args.root.resolve(),args.device,args.os,args.automatic,args.attempt) else 1)

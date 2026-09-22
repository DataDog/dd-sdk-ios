"""Bounded child supervision; preserves bytes before parsing operator messages."""
import codecs
import os
from pathlib import Path
import selectors
import signal
import subprocess
import time
import human_build
from acceptance_common import require
import human_processes
import s2_hosting_workflow as shared


def supervise(argv, log_path, on_message, execution_deadline, cleanup_deadline):
    import json
    require(time.time()<execution_deadline<cleanup_deadline,'closed child budget')
    # Reserve and prove log publication before the child can perform native work.
    with Path(log_path).open('xb') as log:
        log.flush();os.fsync(log.fileno())
        child=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,start_new_session=True)
        reader=selectors.DefaultSelector();reader.register(child.stdout,selectors.EVENT_READ)
        decoder=codecs.getincrementaldecoder('utf-8')();pending='';stopping=False;problem=None;cleanup_entered=False
        def stop():
            nonlocal stopping
            if not stopping and child.poll() is None:
                os.killpg(child.pid,signal.SIGTERM);stopping=True
        def retain(chunk):
            nonlocal pending,cleanup_entered
            log.write(chunk);log.flush()
            pending+=decoder.decode(chunk)
            while '\n' in pending:
                line,pending=pending.split('\n',1)
                try:message=json.loads(line)
                except json.JSONDecodeError:continue
                if isinstance(message,dict):
                    if 'cell_phase' in message:
                        phase=message['cell_phase']
                        require(not cleanup_entered and phase['phase']=='cleanup' and phase['execution_deadline']<=execution_deadline
                                and phase['at']<=time.time() and phase['at']<=phase['cleanup_deadline']<=cleanup_deadline,'invalid child cleanup boundary')
                        cleanup_entered=True
                    on_message(message)
        try:
            while reader.get_map():
                if not cleanup_entered and time.time()>=execution_deadline:stop()
                require(time.time()<cleanup_deadline,'child exceeded fixed cleanup deadline')
                for key,_ in reader.select(timeout=min(.25,max(0,cleanup_deadline-time.time()))):
                    chunk=os.read(key.fileobj.fileno(),65536)
                    if chunk:retain(chunk)
                    else:reader.unregister(key.fileobj)
            pending+=decoder.decode(b'',final=True)
            require(not pending,'unterminated child publication')
            code=child.wait(timeout=max(.001,cleanup_deadline-time.time()))
            require(not stopping,'child exceeded fixed execution deadline')
            return code
        except BaseException as error:
            problem=error;stop()
            # Keep serving cleanup prompts after an interruption or evidence
            # failure. The original cleanup clock is the only remaining budget.
            while reader.get_map() and time.time()<cleanup_deadline:
                for key,_ in reader.select(timeout=min(.25,max(0,cleanup_deadline-time.time()))):
                    chunk=os.read(key.fileobj.fileno(),65536)
                    if chunk:
                        try:retain(chunk)
                        except Exception:pass
                    else:reader.unregister(key.fileobj)
            try:child.wait(timeout=max(.001,cleanup_deadline-time.time()))
            except subprocess.TimeoutExpired:
                try:os.killpg(child.pid,signal.SIGKILL)
                except OSError:
                    # EOF/exit can race the final signal; an empty actual group
                    # and a reaped child are required before treating it as gone.
                    if human_processes.members(child.pid):raise
                child.wait(timeout=5)
            raise
        finally:
            reader.close();child.stdout.close()
            receipt=human_processes.quiesce(child.pid,cleanup_deadline)
            receipt['child_exit']=child.returncode
            shared.save(Path(log_path).with_suffix('.supervisor.json'),receipt,exclusive=True)
            log.flush();os.fsync(log.fileno())
            if problem is None:require(receipt['state']=='PASS' and not receipt['before'],'owned child group was not absent at normal completion')

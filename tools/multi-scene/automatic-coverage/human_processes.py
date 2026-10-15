"""Own one native cell process group; never mutate the shared prepared helpers."""
from contextlib import contextmanager
import os
import signal
import subprocess
import time
from acceptance_common import require


def members(group):
    # The inventory reader has its own group, so it cannot observe itself as a
    # native worker. Only exact members of our freshly created group are selected.
    result=subprocess.run(['/bin/ps','-axo','pid=,pgid='],capture_output=True,text=True,
                          start_new_session=True,timeout=3,check=True)
    return sorted(int(pid) for pid,pgid in (line.split() for line in result.stdout.splitlines()) if int(pgid)==group)


def quiesce(group,deadline,*,exempt=()):
    require(group>1 and (group!=os.getpgrp() or os.getpid() in exempt),'refuse unrelated/current process group')
    started=time.time();before=[pid for pid in members(group) if pid not in exempt];signalled=[]
    for sig,seconds in [(signal.SIGTERM,1),(signal.SIGKILL,2)]:
        current=[pid for pid in members(group) if pid not in exempt]
        for pid in current:
            try:os.kill(pid,sig);signalled.append({'pid':pid,'signal':int(sig)})
            except ProcessLookupError:pass
        limit=min(deadline,time.time()+seconds)
        while current and time.time()<limit:
            time.sleep(.05);current=[pid for pid in members(group) if pid not in exempt]
        if not current:break
    after=[pid for pid in members(group) if pid not in exempt];finished=time.time()
    return {'state':'PASS' if not after and finished<=deadline else 'INVALID','group':group,'exempt':list(exempt),
            'started_at':started,'finished_at':finished,'deadline':deadline,'before':before,'remaining':after,
            'signals':signalled,'quiescent':not after}


@contextmanager
def shared_commands(shared):
    """Only the supervised child may use this adapter. Capture already inherits it.

    All command descendants now stay in the child's dedicated group. At native
    exit they are reaped before task teardown; the parent verifies group absence
    after the child exits. No input worker or command can escape via our helpers.
    """
    require(os.getpgrp()==os.getpid(),'cell requires its dedicated supervisor group')
    original=shared.command
    def command(argv,folder,name,*,deadline,cwd=None):
        require(time.time()<deadline,'command after fixed deadline')
        from pathlib import Path
        log=Path(folder)/(name+'.log');started=time.time()
        with log.open('x') as stream:
            process=subprocess.Popen(argv,cwd=cwd,env=shared.environment(),stdout=stream,stderr=subprocess.STDOUT)
            try:process.wait(timeout=max(.001,deadline-time.time()))
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:process.wait(timeout=min(1,max(.001,deadline-time.time())))
                    except subprocess.TimeoutExpired:process.kill();process.wait(timeout=1)
        shared.save(Path(folder)/(name+'.json'),{'argv':argv,'started_at':started,'finished_at':time.time(),
                    'returncode':process.returncode,'log_sha256':shared.sha(log),'owned_group':os.getpgrp()},exclusive=True)
        require(process.returncode==0 and time.time()<deadline,name+' failed or late')
    shared.command=command
    try:yield
    finally:shared.command=original

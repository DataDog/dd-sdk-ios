"""Bounded Off-cell process custody and guarded publication. No SDK code."""
from pathlib import Path
import hashlib,json,os,signal,subprocess,sys,time,uuid

def digest(data):
    return hashlib.sha256(data).hexdigest()

def sync_directory(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)

def publish(path, value, join=lambda: None):
    path = Path(path)
    payload = (json.dumps(value, indent=2) + '\n').encode()
    issued = {'path': str(path), 'sha256': digest(payload)}
    created = False
    join()
    try:
        with path.open('xb') as stream:
            created = True
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        sync_directory(path.parent)
        assert not path.is_symlink() and path.read_bytes() == payload
        join()
        assert not path.is_symlink() and path.read_bytes() == payload
        return issued
    except BaseException:
        # The namespace was absent before this attempt. Preserve any substituted
        # bytes separately, but never leave an issued positive receipt canonical.
        if created and os.path.lexists(path):
            os.rename(path, path.with_name(path.name + '.withdrawn-' + uuid.uuid4().hex))
            sync_directory(path.parent)
        raise

def group_observation(pgid, cutoff):
    assert time.time() < cutoff, "Group observation reservation expired"
    try:
        os.killpg(pgid, 0)
        return {'present': True, 'probe': 'killpg_zero'}
    except ProcessLookupError:
        return {'present': False, 'probe': 'killpg_ESRCH'}
    except PermissionError:
        # EPERM is not absence. Obtain a separate actual process inventory;
        # if that inventory fails, propagate uncertainty instead of accepting.
        remaining = cutoff - time.time()
        assert remaining > 0
        raw = subprocess.check_output(['/bin/ps', '-axo', 'pid,pgid'], text=True, timeout=remaining)
        assert time.time() < cutoff, 'Inventory completed after issued cleanup cutoff'
        rows = [list(map(int, line.split())) for line in raw.splitlines()[1:]]
        assert all(len(row) == 2 for row in rows)
        owned = [row for row in rows if row[1] == pgid]
        return {'present': bool(owned), 'probe': 'ps_pid_pgid_after_EPERM', 'owned_rows': owned}

def cleanup_group(child, pgid, cutoff):
    errors, interruptions = [], []
    def remember(error):
        name = type(error).__name__
        errors.append(name)
        if not isinstance(error, Exception):
            interruptions.append(name)
    def observe():
        try:
            return group_observation(pgid, cutoff)
        except BaseException as error:
            remember(error)
            return {'present': None, 'probe_failure': type(error).__name__}
    def reap():
        try:
            child.poll()
        except BaseException as error:
            remember(error)
    # Defer supported termination while cleaning up. Preserve it as a stopped
    # operation, but let the owned group reach KILL/reaping inside its cutoff.
    previous = {}
    def deferred(signum, frame):
        errors.append('signal:' + str(signum))
        interruptions.append('KeyboardInterrupt')
    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
        try:
            old = signal.getsignal(sig)
            signal.signal(sig, deferred)
            previous[sig] = old
        except BaseException as error:
            remember(error)
    try:
        try:
            if child.stdin is not None and not child.stdin.closed:
                child.stdin.close()
        except BaseException as error:
            remember(error)
        for sig, grace in [(signal.SIGTERM, 2), (signal.SIGKILL, None)]:
            try:
                reap()
                if observe()['present'] is False or time.time() >= cutoff:
                    break
                for attempt in range(2):
                    try:
                        os.killpg(pgid, sig)
                        break
                    except ProcessLookupError:
                        break
                    except BaseException as error:
                        remember(error)
                        if isinstance(error, Exception) or attempt or time.time() >= cutoff:
                            break
                end = cutoff if grace is None else min(time.time() + grace, cutoff - .1)
                while time.time() < end:
                    reap()
                    if observe()['present'] is False:
                        break
                    try:
                        time.sleep(.02)
                    except BaseException as error:
                        remember(error)
                        break  # Escalate from TERM rather than abandon cleanup.
            except BaseException as error:
                remember(error)
    finally:
        reap()
        observation = observe()
        for sig, old in previous.items():
            try:
                signal.signal(sig, old)
            except BaseException as error:
                remember(error)
    return {'owned_group_absent': observation['present'] is False and time.time() < cutoff,
            'absence_observation': observation, 'signal_errors': errors,
            'interruption_type': interruptions[0] if interruptions else None,
            'cutoff': cutoff, 'completed_at': time.time()}

def checked_interpreter():
    if not __debug__ or sys.flags.optimize:
        raise RuntimeError('qualification requires an unoptimized interpreter')


def checked_environment(env):
    checked_interpreter()
    if env.get('PYTHONOPTIMIZE') not in (None, '', '0'):
        raise RuntimeError('inherited Python optimization is forbidden')
    if 'XCODE_XCCONFIG_FILE' in env:
        raise RuntimeError('external build configuration is not bound')


def device_identity(value, declared):
    if not (value.get('udid')==declared['udid'] and value.get('name')==declared['name'] and
            value.get('runtime')==declared['runtime'] and value.get('isAvailable') is True):
        raise RuntimeError('declared simulator identity or availability differs')
    return value


GATED = "import json,os,sys\ncmd=json.loads(sys.argv[1])\nif sys.stdin.buffer.read(1)!=b'G': raise SystemExit(78)\nos.execvpe(cmd[0],cmd,os.environ)"


def install_termination_handlers():
    interrupted=[]
    def stop(signum, frame):
        if not interrupted:
            interrupted.append(signum)
            raise KeyboardInterrupt('owned operation interrupted')
    previous={s:signal.getsignal(s) for s in (signal.SIGTERM,signal.SIGINT,signal.SIGHUP)}
    for s in previous:signal.signal(s,stop)
    return previous


def process(root, cwd, env, command, name, deadline, cutoff, join=lambda:None, release=None):
    checked_environment(env)
    if not time.time()<deadline<cutoff:raise RuntimeError('operation reservation expired')
    root=Path(root);stdout=root/(name+'.stdout');stderr=root/(name+'.stderr')
    child=None;pgid=None;registration=None;failure=None;rc=None;disposition=None
    with stdout.open('xb') as out,stderr.open('xb') as err:
        try:
            child_env=dict(env);child_env.pop('PYTHONOPTIMIZE',None)
            child=subprocess.Popen([sys.executable,'-c',GATED,json.dumps(command)],cwd=cwd,env=child_env,
                stdin=subprocess.PIPE,stdout=out,stderr=err,start_new_session=True)
            pgid=child.pid
            if os.getpgid(child.pid)!=pgid:raise RuntimeError('owned group differs')
            registration=publish(root/(name+'-start.json'),dict(pid=pgid,pgid=pgid,command=command,
                deadline=deadline,cleanup_cutoff=cutoff,controller_pid=os.getpid(),created_at=time.time()),join)
            if release:release(registration,pgid,pgid)
            join()
            if time.time()>=deadline:raise RuntimeError('release reservation expired')
            child.stdin.write(b'G');child.stdin.flush();child.stdin.close()
            rc=child.wait(timeout=max(.001,deadline-time.time()))
        except BaseException as error:
            failure=type(error).__name__
        finally:
            if child is not None:
                try:disposition=cleanup_group(child,pgid,cutoff)
                except BaseException as error:disposition=dict(owned_group_absent=False,failure_type=type(error).__name__,completed_at=time.time(),cutoff=cutoff)
                failure=failure or disposition.get('interruption_type')
                rc=child.returncode if rc is None else rc
            else:disposition=dict(owned_group_absent=True,child_created=False,completed_at=time.time(),cutoff=cutoff)
    observed=dict(returncode=rc,timed_out=failure=='TimeoutExpired',exception_type=failure,start=registration,
        pid=pgid,pgid=pgid,command=command,deadline=deadline,cleanup_cutoff=cutoff,cleanup=disposition,
        stdout=dict(path=str(stdout),sha256=digest(stdout.read_bytes())),stderr=dict(path=str(stderr),sha256=digest(stderr.read_bytes())),
        owned_group_absent=disposition['owned_group_absent'],completed_at=time.time())
    try:outcome=publish(root/(name+'-outcome.json'),observed)
    except BaseException:
        publish(root/(name+'-publication-stop.json'),observed)
        raise
    return rc,stdout.read_bytes(),outcome,registration,disposition['owned_group_absent']


checked_interpreter()

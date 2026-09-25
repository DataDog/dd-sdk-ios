"""Signed-in F08 identity and task-only capture retention; never read credentials."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import stat
import time
import uuid

import journey_builds as builds
import journey_contract as contract
from capture_io import atomic, encoded
from capture_contract import loads, MAX_BYTES
from acceptance_common import require
import s2_hosting_workflow as shared
from s2_webview_driver import display
from s2_webview_runtime import active_display, display_signature

MODE = 'signed-in-smoke'
CAPTURE_NAME = re.compile(r'rum-release-capture-([0-9a-f-]{36})')
REQUEST = 'release-capture-request.json'


def digest_subject(event, salt):
    require(isinstance(salt, str) and str(uuid.UUID(salt)) == salt, 'account comparison salt differs')
    values = {name: contract.field(event, name) for name in ['usr.id', 'usr.org_uuid']}
    require(all(isinstance(v, str) and 0 < len(v) <= 512 for v in values.values()),
            'authenticated user or organization identity missing')
    return {name: hashlib.sha256(encoded([salt, name, 'string', value])).hexdigest()
            for name, value in values.items()}


def subject(rows, ready, salt):
    sequence = ready['snapshot']['sequence']
    owner = ready['owner']['view_id']
    events = [(r['sequence'], loads(r['fields']['event_json'])) for r in rows
              if r['kind'] == 'mapper' and r['sequence'] < sequence]
    views = [(seq, event) for seq, event in events if event['type'] == 'view'
             and contract.field(event, 'view.id') == owner]
    require(views, 'authenticated boundary view missing')
    seq, event = views[-1]
    digests = digest_subject(event, salt)
    # Earlier startup observations may precede configureAnalytics. A non-null
    # conflicting identity may never be silently accepted as startup traffic.
    for _, value in events:
        if contract.field(value, 'usr.org_uuid') is not None:
            require(digest_subject(value, salt) == digests, 'account changed before Services readiness')
    return dict(state='AUTHENTICATED_CAPTURE_BOUND', digests=digests,
                boundary_sequence=sequence, view_sequence=seq, view_id=owner,
                account_salt_sha256=hashlib.sha256(salt.encode()).hexdigest())


def verify_subject(rows, ready, salt, binding):
    require(subject(rows, ready, salt) == binding, 'authenticated boundary binding changed')
    for row in rows:
        if row['kind'] == 'mapper' and row['sequence'] >= binding['boundary_sequence']:
            require(digest_subject(loads(row['fields']['event_json']), salt) == binding['digests'],
                    'account changed or disappeared after Services readiness')
    return binding


def receipt(binding, *, device, bundle, product_sha256, keychain_group, organization):
    path = Path(binding['path']).resolve(strict=True)
    require(builds.sha(path) == binding['sha256'], 'account setup receipt changed')
    value = loads(path.read_bytes())
    require(value['state'] == 'SIGNED_ACCOUNT_SETUP_QUALIFIED' and value['capture_enabled'] is False
            and value['device'] == device and value['bundle_id'] == bundle
            and value['product_manifest_sha256'] == product_sha256
            and value['keychain_group'] == keychain_group and value['organization'] == organization,
            'account setup belongs to another product, device or organization')
    require(set(value['observations']) == {'profile', 'organization', 'services'}, 'account setup UI witnesses missing')
    for observation in value['observations'].values():
        item = Path(observation['path']).resolve(strict=True)
        require(item.is_relative_to(path.parent) and not item.is_symlink()
                and builds.sha(item) == observation['sha256'], 'account setup witness changed')
    require(value['services_loaded'] is True and value['profile_observed'] is True,
            'account setup did not reach a real authenticated service list')
    return value


def inventory(root):
    """Hash Documents in place; do not copy unrelated app/user data."""
    root = Path(root)
    require(root.is_dir() and not root.is_symlink(), 'unsafe Documents directory')
    files = {}
    for item in root.rglob('*'):
        require(not item.is_symlink(), 'symlink in retained Documents')
        if item.is_file():
            require(stat.S_ISREG(item.stat().st_mode), 'non-regular retained document')
            files[str(item.relative_to(root))] = dict(sha256=builds.sha(item), size=item.stat().st_size)
    return files


def capture_roots(documents):
    roots = []
    for path in Path(documents).iterdir():
        match = CAPTURE_NAME.fullmatch(path.name)
        if match:
            require(str(uuid.UUID(match[1])) == match[1] and path.is_dir() and not path.is_symlink(),
                    'invalid prior capture directory')
            files = inventory(path)
            require({'events.jsonl','encoder-setup.json'} <= set(files) and
                    all(n in {'events.jsonl','encoder-setup.json'} or re.fullmatch(r'checkpoint-(?:[0-9a-f-]{36}|background-[0-9]+)\.json',n) for n in files),
                    'unknown file in prior capture directory')
            setup=loads((path/'encoder-setup.json').read_bytes())
            require(setup['identity']['run_id']==match[1], 'prior capture identity differs from directory')
            require(sum(v['size'] for v in files.values()) <= 4 * MAX_BYTES, 'prior capture exceeds archive bound')
            roots.append(path)
    request = Path(documents) / REQUEST
    if request.exists() or request.is_symlink():
        require(not request.is_symlink() and request.is_file() and request.stat().st_size <= 16384,
                'unsafe old recorder request')
        value = loads(request.read_bytes())
        require('rum-release-capture-' + value['run_id'] in {p.name for p in roots},
                'old recorder request lacks its capture directory')
        roots.append(request)
    return sorted(roots)


def preserve_capture(documents, destination, *, move=False):
    roots = capture_roots(documents)
    destination = Path(destination); destination.mkdir(mode=0o700)
    before = inventory(documents)
    for source in roots:
        target = destination / source.name
        if source.is_dir(): shutil.copytree(source, target)
        else: shutil.copy2(source, target)
    copied = inventory(destination)
    names = {p.name for p in roots}
    selected = {name: value for name, value in before.items() if Path(name).parts[0] in names}
    require(copied == selected, 'recorder archive readback differs')
    if move:
        for source in roots:
            if source.is_dir(): shutil.rmtree(source)
            else: source.unlink()
        require(inventory(documents) == {n:v for n,v in before.items() if n not in selected},
                'unrelated Documents changed during recorder archival')
    atomic(destination / 'archive-receipt.json', encoded(dict(files=copied, moved=move)))
    return copied


def device_processes(device, out, label, deadline):
    path=Path(out)/(label+'.raw.json')
    shared.command(['xcrun','devicectl','device','info','processes','--device',device,
                    '--timeout','15','--json-output',str(path)],out,label,deadline=min(deadline,time.time()+20))
    value=loads(path.read_bytes());info=value.get('info',{});arguments=info.get('arguments',[])
    require(info.get('outcome')=='success' and info.get('commandType')=='devicectl.device.info.processes'
            and '--device' in arguments and arguments[arguments.index('--device')+1]==device
            and value.get('result',{}).get('deviceIdentifier')==device,'foreign device process inventory')
    rows=value['result']['runningProcesses']
    require(isinstance(rows,list) and all(type(r.get('processIdentifier')) is int and r['processIdentifier']>0 for r in rows),
            'invalid device process inventory')
    return {r['processIdentifier'] for r in rows}


def main_processes(executable):
    rows=shared.capture(['ps','-axo','pid=,comm=']).stdout.decode().splitlines()
    return [int(v[0]) for line in rows if len(v:=line.strip().split(None,1))==2 and v[1]==str(executable)]


def stop_exact(device, bundle, executable, out, label, deadline, *, pid=None):
    """Bind device PID membership to its exact host executable; ignore extensions."""
    # A missing launch receipt cannot grant an absence verdict. In particular,
    # never stop a guessed replacement after a failed launch-output parse.
    require(type(pid) is int and pid>0,'unknown task PID; process absence cannot be certified')
    before=device_processes(device,out,label+'-before',deadline)
    matching=main_processes(executable)
    require(not matching or matching==[pid],'task main process replaced or ambiguous')
    host=shared.process(pid)
    if pid not in before:
        require(not host and not matching,'host/device process absence disagrees')
        return dict(state='QUIESCENT',pid=pid,stopped=False)
    require(host==str(executable) and matching==[pid],'recorded device PID has a different or unproven executable')
    shared.command(['xcrun','simctl','terminate',device,bundle],out,label,
                   deadline=min(deadline,time.time()+30))
    for index in range(30):
        require(time.time()<deadline,'task main process did not stop')
        after=device_processes(device,out,label+'-after-'+str(index),deadline)
        host=shared.process(pid);matching=main_processes(executable)
        require(not matching or matching==[pid],'replacement main process appeared during cleanup')
        if pid not in after and not host and not matching:
            return dict(state='QUIESCENT',pid=pid,stopped=True)
        time.sleep(.1)
    require(False,'recorded task PID remains after termination')


def retained_cleanup(out, documents, device, original_device, original_apps, initial, pid,
                     installed, qualified, verify_source, deadline):
    errors = []; bundle = qualified['identity']['bundle_id']
    def attempt(label, action):
        try:
            require(time.time() < deadline, 'retention cleanup deadline expired')
            return action()
        except Exception as error:
            errors.append(label + ': ' + str(error))
    if installed is not None:
        attempt('terminate task', lambda: stop_exact(device,bundle,installed/qualified['identity']['executable'],
                out,'retained-stop',deadline,pid=pid))
    if documents is not None and documents.is_dir():
        attempt('preserve native evidence', lambda: preserve_capture(documents,out/'native-preserved'))
    if installed is not None:
        attempt('retained product', lambda: builds.product(installed,qualified['manifest']))
    def non_task_apps():
        actual = shared.apps(device)
        require({k:v for k,v in actual.items() if k!=bundle} == {k:v for k,v in original_apps.items() if k!=bundle}
                and bundle in actual, 'non-task app inventory or retained task changed')
    attempt('app inventory', non_task_apps)
    def device_state():
        actual = shared.devices(device)
        require(all(actual[k] == original_device[k] for k in ['udid','state','runtime','deviceTypeIdentifier']),
                'original device state changed')
    attempt('device restoration', device_state)
    if initial is not None:
        def geometry():
            actual = display(device,out,'retained-display',deadline)
            require(display_signature(active_display(loads(actual),device)) ==
                    display_signature(active_display(loads(initial),device)), 'original display changed')
        attempt('display restoration', geometry)
    attempt('workspace/source identity', verify_source)
    atomic(out/'account-retention.json',encoded(dict(state='PASS' if not errors else 'INVALID',
           errors=errors,task_installed=installed is not None,account_retained=not errors,credential_exports=0,uninstalls=0,
           finished_at=time.time(),deadline=deadline)))
    return errors

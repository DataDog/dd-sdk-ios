"""Finite input sequencing. Native effects stay in the supported-tool connector."""
import argparse
import json
from pathlib import Path
import sys
import time
import uuid
import capture_input as c
from capture_io import atomic, encoded

q = c.q
require = c.require
PHASES = ('setup.detail', 'pop.finish', 'setup.detail-again', 'pop.cancel',
          'setup.sheet', 'dismiss.finish', 'setup.sheet-again', 'dismiss.cancel',
          'return.dismiss', 'return.home', 'background')


def locations(root, framework):
    require(framework in ('UIKit', 'SwiftUI'), 'foreign sequence framework')
    root = Path(root).resolve(strict=True)
    return root/'cells'/framework, root/'sessions'/framework/'sequence'


def start(root, framework):
    cell, folder = locations(root, framework)
    plan, compiled, products = q.reviewed(Path(root))
    summary = q.shared.read(cell/'summary.json')
    require(summary['state'] == 'RUNNING' and summary['cleanup'] == 'NOT_STARTED'
            and time.time() < summary['native_deadline'], 'native cell cannot admit input')
    item = products['products'][framework]; arm = compiled['arms']['A-simulator']
    identity = summary['identity']
    require(identity['bundle'] == item['bundle'] and identity['source'] == arm['source']
            and identity['fixture'] == arm['fixture'] and identity['framework'] == framework
            and type(identity.get('pid')) is int and identity['pid'] > 0, 'foreign native cell identity')
    session_path = folder.parent/'start.json'
    session = q.tool_value(q.shared.read(session_path)['actual_return'])
    require(session['deviceUUID'] == plan['device']['udid'] and session['deviceIsSimulator'] is True
            and q.shared.read(folder.parent/'qualified.json')['state'] == 'PASS', 'unqualified input session')
    process = q.driver.process_identity(identity['pid'])
    require(process is not None, 'native process absent')
    folder.mkdir();(folder/'exchanges').mkdir();(folder/'received').mkdir()
    binding = dict(root=str(Path(root).resolve()), framework=framework, identity=identity,
        device=plan['device']['udid'], process_identity=process, session_key=session['interactionSessionKey'],
        session_sha256=q.shared.sha(session_path), plan_sha256=q.shared.sha(Path(root)/'plan.json'),
        native_deadline=summary['native_deadline'], cleanup_deadline=summary['cleanup_deadline'], phase_count=len(PHASES))
    atomic(folder/'binding.json', encoded(binding))
    return dict(state='BOUND', binding_sha256=q.shared.sha(folder/'binding.json'), **binding)


def binding_for(root, framework, payload, *, current=True):
    cell, folder = locations(root, framework)
    binding = q.shared.read(folder/'binding.json')
    require(payload.get('binding_sha256') == q.shared.sha(folder/'binding.json')
            and binding['root'] == str(Path(root).resolve()) and binding['framework'] == framework
            and binding['phase_count'] == len(PHASES), 'foreign sequence binding')
    if current:
        require(q.shared.sha(Path(root)/'plan.json') == binding['plan_sha256']
                and q.shared.sha(folder.parent/'start.json') == binding['session_sha256'], 'sequence plan or session changed')
        require(all(q.shared.sha(q.shared.REPO/name) == digest for name,digest in
                    q.shared.read(Path(root)/'plan.json')['helpers'].items()), 'sequence helper source changed')
    return cell, folder, binding


def request_at(cell, phase):
    paths = [p for p in (cell/'input').glob('*/prompt.json') if q.shared.read(p)['phase'] == phase]
    require(len(paths) == 1 and not paths[0].is_symlink(), 'missing or duplicate sequence request')
    return paths[0]


def progress(cell, folder, binding):
    paths = sorted((folder/'exchanges').glob('*.json'))
    require(len(paths) <= len(PHASES) and {p.name for p in paths} == {str(i)+'.json' for i in range(len(paths))},
            'skipped or duplicate sequence exchange')
    for index in range(len(paths)):
        row = q.shared.read(folder/'exchanges'/(str(index)+'.json'))
        require(row['index'] == index and row['phase'] == PHASES[index]
                and row['binding_sha256'] == q.shared.sha(folder/'binding.json'), 'reordered or foreign sequence exchange')
        result = row['result']; request = request_at(cell, PHASES[index])
        require(result.get('state') == 'PUBLISHED' and result.get('dispatch_attempted') is True
                and result.get('local_pending') is None, 'prior sequence exchange incomplete or uncertain')
        require(result.get('before') == q.shared.read(request.with_name('worker-before.json'))
                and result.get('action') == q.shared.read(request.with_name('worker-action.json')),
                'actual sequence exchange changed')
        proof = q.completed_input(request)
        require(proof.get('input_complete') is True, 'prior input not complete')
    return len(paths)


def next_request(root, framework, payload):
    cell, folder, binding = binding_for(root, framework, payload)
    require(not (folder/'stop.json').exists(), 'input sequence already stopped')
    index = progress(cell, folder, binding)
    require(type(payload.get('index')) is int and payload['index'] == index, 'skipped or replayed sequence index')
    poll_end = min(binding['native_deadline'], time.time()+10)
    while True:
        require(not (folder/'stop.json').exists(), 'input sequence stopped while waiting')
        summary = q.shared.read(cell/'summary.json')
        require(summary['identity'] == binding['identity'] and summary['native_deadline'] == binding['native_deadline']
                and summary['cleanup_deadline'] == binding['cleanup_deadline'],
                'native sequence identity or deadline changed')
        if summary['state'] != 'RUNNING' or summary['cleanup'] != 'NOT_STARTED':
            return dict(state='TERMINAL', completed=index, scenario=summary['scenario'], evidence=summary['evidence'], cleanup=summary['cleanup'])
        require(time.time() < binding['native_deadline'], 'original native sequence deadline expired')
        require(q.driver.process_identity(binding['identity']['pid']) == binding['process_identity'], 'sequence process replaced')
        requests = [(p, q.shared.read(p)) for p in (cell/'input').glob('*/prompt.json')]
        require(len({v['phase'] for _,v in requests}) == len(requests), 'duplicate native input phase')
        require(all(v['phase'] in PHASES[:min(index+1, len(PHASES))] for _,v in requests), 'skipped or reordered native input phase')
        current = [(p,v) for p,v in requests if index < len(PHASES) and v['phase'] == PHASES[index]]
        if current:
            path, request = current[0]
            require(request['run_id'] == binding['identity']['run_id'] and request['app_pid'] == binding['identity']['pid']
                    and request['app_bundle'] == binding['identity']['bundle'] and request['device'] == binding['device']
                    and request['process_identity'] == binding['process_identity']
                    and c.session_key(path) == binding['session_key'], 'foreign sequence request owner')
            require(request['deadline'] <= binding['native_deadline'], 'input deadline extends original native bound')
            c.pending(path, time.time())
            return dict(state='REQUEST', index=index, phase=PHASES[index], request=str(path),
                        deadline=request['deadline'], session_key=binding['session_key'])
        if time.time() >= poll_end:
            return dict(state='WAIT', index=index)
        time.sleep(0.1)


def stop(root, framework, payload):
    _, folder, _ = binding_for(root, framework, payload, current=False)
    path = folder/'stop.json'
    if not path.exists():
        atomic(path, encoded(dict(at=time.time(), state='STOPPED', payload=payload,
            scope='Worker transport result only; not input completion, native idle, release or cleanup proof')))
    return dict(state='STOPPED', receipt=str(path))


def record(root, framework, payload):
    # Retain even malformed, late or duplicate exchanges without replacing evidence.
    _, folder = locations(root, framework)
    receipt = folder/'received'/(uuid.uuid4().hex+'.json')
    atomic(receipt, encoded(dict(at=time.time(), payload=payload)))
    try:
        cell, folder, binding = binding_for(root, framework, payload)
        index = payload.get('index')
        require(type(index) is int and 0 <= index < len(PHASES), 'invalid sequence result index')
        require(not (folder/'stop.json').exists(), 'sequence result after stop')
        require(progress(cell, folder, binding) == index, 'skipped or replayed result index')
        row = dict(payload, phase=PHASES[index], recorded_at=time.time(), receipt=str(receipt))
        atomic(folder/'exchanges'/(str(index)+'.json'), encoded(row))
        require(progress(cell, folder, binding) == index+1, 'unpublished preceding exchange')
        return dict(state='RECORDED', next_index=index+1, receipt=str(receipt))
    except Exception as error:
        result = dict(state='STOPPED', reason=type(error).__name__+': '+str(error), receipt=str(receipt))
        try:
            stop(root, framework, dict(payload, reason=result['reason'], receipt=str(receipt)))
        except Exception as failure:
            result['stop_error'] = type(failure).__name__+': '+str(failure)
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['bind','next','record','stop'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--framework', choices=['UIKit','SwiftUI'], required=True)
    args = parser.parse_args()
    payload = json.load(sys.stdin)
    result = start(args.root,args.framework) if args.stage == 'bind' else globals()[{'next':'next_request'}.get(args.stage,args.stage)](args.root,args.framework,payload)
    print(json.dumps(result),flush=True)


if __name__ == '__main__':
    main()

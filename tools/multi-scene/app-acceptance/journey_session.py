#!/usr/bin/env python3
"""Use the existing human prompt page and owned child supervisor for one F08 arm."""
import argparse
import json
from pathlib import Path
import sys
import time

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_operator as operator
import human_supervisor as supervisor
import human_processes as processes
import journey_workflow as workflow
from capture_io import atomic, encoded
from capture_contract import loads
from acceptance_common import require


def qualify(root, arm, *, error=None):
    folder=root/'cells'/arm;result_path=folder/'summary.json'
    result=loads(result_path.read_bytes()) if result_path.exists() else None
    path=root/(arm+'-driver.supervisor.json');worker=loads(path.read_bytes()) if path.exists() else None
    publication=folder/'summary-publication.json'
    ready=bool(result and not error and result.get('mechanism',{}).get('state')=='PASS'
               and worker and worker['state']=='PASS' and not worker['before'] and not worker['remaining']
               and publication.exists() and not (folder/'late-summary-publication.json').exists())
    if ready:
        receipt=loads(publication.read_bytes())
        ready=(receipt['summary_sha256']==workflow.builds.sha(result_path)
               and receipt['published_at']<receipt['deadline']==result['cleanup_details']['deadline']
               and publication.stat().st_mtime<receipt['deadline']
               and worker['finished_at']<result['cleanup_deadline'] and time.time()<result['cleanup_deadline'])
    record=dict(state='PASS' if ready else 'UNQUALIFIED',arm=arm,finished_at=time.time(),
                plan_sha256=workflow.builds.sha(root/'plan.json'),
                summary_sha256=workflow.builds.sha(result_path) if result else None,
                publication_sha256=workflow.builds.sha(publication) if publication.exists() else None,
                supervisor=dict(path=str(path),sha256=workflow.builds.sha(path)) if worker else None,
                error=error,release_acceptance=False,gates_closed=[])
    atomic(root/(arm+'-qualification.json'),encoded(record))
    if result and time.time()>=result['cleanup_deadline']:
        atomic(root/(arm+'-late-qualification.json'),encoded(dict(state='INVALID',observed_at=time.time(),deadline=result['cleanup_deadline'])))
        return False
    return ready


def run(args):
    root=args.root.resolve(strict=True);plan=workflow.verify(root)
    workflow.validate_native_admission(root,args.device)
    require(not (root/(args.arm+'-driver.log')).exists(),'consumed F08 arm; no input retry')
    # Both source/product checks finish before the fixed native clock begins.
    workflow.builds.verify(plan['build_root'],args.arm,plan['completion_sha256'],runtime_transition=plan.get('runtime_transition'))
    operator.publish(root/'operator',dict(instruction='Preparing the app. Wait for its ready step.'),context='F08 / '+args.arm)
    budget=plan['definition']['limits'];native=time.time()+budget['native_seconds_per_arm']
    execution=native+budget['backend_seconds_per_arm'];cleanup=execution+budget['cleanup_seconds']
    argv=[sys.executable,'-B',str(Path(workflow.__file__).resolve()),'cell','--root',str(root),'--arm',args.arm,
          '--device',args.device,'--native-deadline',str(native),'--execution-deadline',str(execution),'--cleanup-deadline',str(cleanup)]
    def message(value):
        operator.forward(root/'operator',value,context='F08 / '+args.arm)
        # Backend requests are consumed by the existing tool orchestrator. All
        # human progress and response publication remain local to the harness.
        if any(key in value for key in ['backend_request','cell_phase','human_release']):print(json.dumps(value),flush=True)
    problem=None
    try:code=supervisor.supervise(argv,root/(args.arm+'-driver.log'),message,execution,cleanup)
    except BaseException as error:problem=str(error);code=1
    ready=qualify(root,args.arm,error=problem)
    operator.publish(root/'operator',dict(instruction='This app journey is captured; wait for review.' if ready else
        'The app journey stopped. Do not repeat input; evidence and cleanup require review.'),context='F08 / '+args.arm)
    print(json.dumps(dict(state='MECHANISM_QUALIFIED' if ready else 'STOPPED',arm=args.arm,release_acceptance=False)),flush=True)
    return 0 if code==0 and ready else 1


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--arm',choices=workflow.builds.ARMS,required=True);parser.add_argument('--device',required=True)
    return run(parser.parse_args())
if __name__=='__main__':raise SystemExit(main())

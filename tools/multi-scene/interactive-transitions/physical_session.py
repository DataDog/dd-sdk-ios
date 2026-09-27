#!/usr/bin/env python3
"""Supervise one reviewed physical cell and publish the existing human page."""
import argparse
import json
from pathlib import Path
import sys
import time
import physical_runtime as runtime
import human_supervisor as supervisor
import human_processes
import human_operator as operator
import journey_session


def run(args):
    root=args.root.resolve();plan=runtime.reviewed(root)
    runtime.require(not runtime.automatic.mode(plan),'automatic input requires physical_automatic.py; human supervisor is unavailable')
    runtime.admit(root,args.key,plan)
    runtime.require(not (root/(args.key+'-driver.log')).exists(),'physical cell already consumed')
    operator.publish(root/'operator',dict(instruction='Preparing the physical app. Wait for the next ready step.'),context=args.key)
    now=time.time();native=now+plan['native_seconds'];execution=native+plan['backend_seconds'];cleanup=execution+plan['cleanup_seconds']
    argv=[sys.executable,'-B',str(Path(runtime.__file__).resolve()),'cell','--root',str(root),'--key',args.key,
          '--native-deadline',str(native),'--execution-deadline',str(execution),'--cleanup-deadline',str(cleanup)]
    def message(value):
        if 'human_release' in value:
            operator.publish(root/'operator',value['human_release'],context=args.key,cleanup=True)
        else:operator.forward(root/'operator',value,context=args.key)
        if any(k in value for k in ['human_input','backend_request','cell_phase','human_release']):print(json.dumps(value),flush=True)
    problem=None;original=human_processes.members;human_processes.members=runtime.io.members
    try:code=supervisor.supervise(argv,root/(args.key+'-driver.log'),message,execution,cleanup)
    except BaseException as error:problem=str(error);code=1
    finally:human_processes.members=original
    ready=runtime.qualify(root,args.key,plan,error=problem)
    operator.publish(root/'operator',dict(instruction='This cell is captured. Wait for review and the next app.' if ready else
        'The test stopped. Do not repeat gestures. Evidence and cleanup are being checked.'),context=args.key)
    scoped=dict(evidence_contract=runtime.rum_outcomes.mode(plan)) if runtime.rum_outcomes.mode(plan) is not None else {}
    state=runtime.rum_outcomes.qualified_state(plan) if scoped and ready else 'MECHANISM_QUALIFIED' if ready else 'STOPPED'
    print(json.dumps(dict(**scoped,state=state,cell=args.key,release_acceptance=False)),flush=True)
    return 0 if code==0 and ready else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--key',required=True)
    raise SystemExit(run(parser.parse_args()))

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
    root=args.root.resolve();plan=runtime.reviewed(root);runtime.admit(root,args.key,plan)
    runtime.require(not (root/(args.key+'-driver.log')).exists(),'physical cell already consumed')
    operator.publish(root/'operator',dict(instruction='Preparing the physical app. Wait for the next ready step.'),context=args.key)
    now=time.time();native=now+1800;execution=native+600;cleanup=execution+300
    argv=[sys.executable,'-B',str(Path(runtime.__file__).resolve()),'cell','--root',str(root),'--key',args.key,
          '--native-deadline',str(native),'--execution-deadline',str(execution),'--cleanup-deadline',str(cleanup)]
    def message(value):
        operator.forward(root/'operator',value,context=args.key)
        if any(k in value for k in ['human_input','backend_request','cell_phase']):print(json.dumps(value),flush=True)
    problem=None;original=human_processes.members;human_processes.members=runtime.io.members
    try:code=supervisor.supervise(argv,root/(args.key+'-driver.log'),message,execution,cleanup)
    except BaseException as error:problem=str(error);code=1
    finally:human_processes.members=original
    ready=journey_session.qualify(root,args.key,error=problem)
    operator.publish(root/'operator',dict(instruction='This cell is captured. Wait for review and the next app.' if ready else
        'The test stopped. Do not repeat gestures. Evidence and cleanup are being checked.'),context=args.key)
    print(json.dumps(dict(state='MECHANISM_QUALIFIED' if ready else 'STOPPED',cell=args.key,release_acceptance=False)),flush=True)
    return 0 if code==0 and ready else 1


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);parser.add_argument('--key',required=True)
    raise SystemExit(run(parser.parse_args()))

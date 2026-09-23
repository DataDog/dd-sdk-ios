#!/usr/bin/env python3
"""One supervised cell in the existing ordered human session; never deliver input."""
import argparse
import json
from pathlib import Path
import sys
import time
import runtime
import human_operator as operator
import human_supervisor as supervisor
import journey_session as shared_session
from acceptance_common import require


def run(args):
    root=args.root.resolve();plan=runtime.reviewed(root)
    runtime.admit(root,args.key,plan,args.device)
    require(not (root/(args.key+'-driver.log')).exists(),'cell driver already consumed; no retry')
    operator.publish(root/'operator',dict(instruction='Preparing the next app. Wait for its ready step.'),context=args.key)
    native,execution,cleanup=runtime.reserve(root,plan,now=time.time())
    argv=[sys.executable,'-B',str(Path(runtime.__file__).resolve()),'cell','--root',str(root),'--key',args.key,'--device',args.device,
          '--native-deadline',str(native),'--execution-deadline',str(execution),'--cleanup-deadline',str(cleanup)]
    def message(value):
        operator.forward(root/'operator',value,context=args.key)
        if 'backend_request' in value or 'cell_phase' in value:print(json.dumps(value),flush=True)
    problem=None
    try:code=supervisor.supervise(argv,root/(args.key+'-driver.log'),message,execution,cleanup)
    except BaseException as error:problem=str(error);code=1
    ready=shared_session.qualify(root,args.key,error=problem)
    operator.publish(root/'operator',dict(instruction='This cell is captured. Wait for the next ready step.' if ready else
        'The cell stopped. Do not repeat input; its evidence and cleanup need review.'),context=args.key)
    if ready and args.key.endswith('-B'):
        try:runtime.compare(root,args.key[:-1]+'A',args.key)
        except Exception as error:
            runtime.shared.save(root/(args.key+'-paired-difference.json'),dict(state='REVIEW_REQUIRED',reason=str(error),at=time.time()),exclusive=True)
            operator.publish(root/'operator',dict(instruction='The source pair differs. Stop input while the evidence is classified.'),context=args.key)
            return 1
    print(json.dumps(dict(state='MECHANISM_QUALIFIED' if ready else 'STOPPED',cell=args.key,release_acceptance=False)),flush=True)
    return 0 if code==0 and ready else 1


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--key',required=True);parser.add_argument('--device',required=True)
    return run(parser.parse_args())
if __name__=='__main__':raise SystemExit(main())

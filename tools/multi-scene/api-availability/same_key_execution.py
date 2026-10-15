#!/usr/bin/env python3
"""Explicit reviewed human setup entry point using the qualified S3 product."""
import argparse
import json
from pathlib import Path
import sys
import time
import same_key_human as preparation
import same_key_contract
import run as runner

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_operator as operator

s=preparation.build.shared


def prepare(root,original):
    s.require(not root.exists(),'human execution output already exists')
    preparation.verify(original,frozen_only=True)
    root.mkdir();(root/'cells').mkdir();(root/'operator').mkdir()
    helpers=preparation.members()
    s.freeze_helpers(root,helpers)
    plan=dict(kind='S3_SAME_KEY_HUMAN_EXECUTION',prepared_at=time.time(),original=str(original),
        original_inputs=preparation.reference(original/'human-inputs.json'),
        source_plan=preparation.reference(original/'plan.json'),product=preparation.reference(original/'simulator/product.json'),
        helpers=helpers,modes=['swift','objc'],setup_seconds=1800,api_seconds=300,cleanup_seconds=300,native_admitted=False)
    s.save(root/'execution-plan.json',plan,exclusive=True)
    operator.publish(root/'operator',{'instruction':'Waiting for reviewed same-key preparation and explicit operator readiness.'})
    verify(root)
    return plan


def verify(root):
    plan=s.read(root/'execution-plan.json');original=Path(plan['original'])
    preparation.verify(original,frozen_only=True)
    s.require(plan['kind']=='S3_SAME_KEY_HUMAN_EXECUTION' and plan['modes']==['swift','objc']
        and (plan['setup_seconds'],plan['api_seconds'],plan['cleanup_seconds'])==(1800,300,300),'changed human execution scope')
    for key,path in [('original_inputs',original/'human-inputs.json'),('source_plan',original/'plan.json'),('product',original/'simulator/product.json')]:
        s.require(plan[key]==preparation.reference(path),'original human build binding changed')
    s.require(s.tree(root/'helpers')==plan['helpers'] and all(s.sha(s.REPO/p)==h for p,h in plan['helpers'].items()),'human execution helpers changed')
    built=s.read(original/'simulator/product.json')
    s.require(s.product(Path(built['path']),preparation.build.BUNDLE)==built['product'],'original human product changed')
    return plan


def execute(root,device,os_version,mode,readiness):
    plan=verify(root);review=s.read(root/'review.json');controls=s.read(root/'controls.json')
    s.require(review['state']==controls['state']=='PASS' and review['reviewer']=='/root/c06_runtime_plan'
        and review['plan_sha256']==controls['plan_sha256']==s.sha(root/'execution-plan.json')
        and review['controls_sha256']==s.sha(root/'controls.json') and controls['helpers']==plan['helpers'],'human execution review stale')
    s.require(mode in plan['modes'],'unadmitted same-key mode')
    existing=list((root/'cells').iterdir())
    if mode=='swift':s.require(not existing,'Swift human cell already consumed')
    else:
        s.require(len(existing)==1 and existing[0].name==os_version+'-swift','qualified same-runtime Swift predecessor required')
        prior=s.read(existing[0]/'summary.json')
        s.require(prior['overall']=='PASS' and prior['cleanup']=='PASS' and prior['device']==device,'Swift predecessor did not qualify')
    operator.ready(root/'operator',s.read(readiness),root/'execution-plan.json',device=device,mode=mode)
    try:
        return runner.run(Path(plan['original']),device,os_version,mode,qualification=same_key_contract,human_setup=True,
            human_verify=lambda:verify(root),output_root=root,
            prompt_channel=lambda message:operator.forward(root/'operator',message,context='S3 same-key '+mode))
    finally:
        operator.publish(root/'operator',{'instruction':'This same-key cell has stopped. Keep input released; evidence and cleanup retain separate verdicts.'})


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','verify','run'])
    parser.add_argument('--root',type=Path,required=True);parser.add_argument('--original',type=Path)
    parser.add_argument('--device');parser.add_argument('--os');parser.add_argument('--mode',choices=['swift','objc'])
    parser.add_argument('--readiness',type=Path);args=parser.parse_args();root=args.root.resolve()
    if args.action=='prepare':
        s.require(args.original is not None,'original build required');prepare(root,args.original.resolve())
    elif args.action=='verify':verify(root)
    else:
        s.require(all([args.device,args.os,args.mode,args.readiness]),'bound native/readiness inputs required')
        return 0 if execute(root,args.device,args.os,args.mode,args.readiness) else 1
    print(json.dumps(dict(state='PREPARED_NATIVE_UNADMITTED',root=str(root),native_launches=0)));return 0


if __name__=='__main__':raise SystemExit(main())

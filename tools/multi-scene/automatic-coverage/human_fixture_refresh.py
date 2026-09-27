#!/usr/bin/env python3
"""Refresh only the passive observer in three existing S2 compiler/source pairs."""
import argparse
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import human_build as build
import human_sessions as sessions

s=build.shared
KEYS=['baseline-26.5','baseline-27.1','candidate-27.1']


def original(root):
    import human_runtime as runner
    return sessions.original(root,runner,allow_backend_decoder_update=True,allow_fixture_refresh=True)


def prepare(root,source):
    base=original(source);source_plan=s.read(source/'build-plan.json')
    s.require(not root.exists(),'fixture refresh already prepared');root.mkdir(parents=True)
    plan=dict(kind='PASSIVE_CLEANUP_OBSERVER_REFRESH',original=str(source),original_plan=sessions.reference(source/'build-plan.json',s),
        original_runtime=sessions.reference(source/'runtime/runtime-plan.json',s),keys=KEYS,arms={},
        observer_sha256=s.sha(build.HERE/'HumanObservation.swift'),protected={p:s.protected()[p] for p in sessions.PROTECTED},
        toolchains=source_plan['toolchains'],helpers={str(Path(__file__).resolve().relative_to(s.REPO)):s.sha(__file__)},native_launches=0)
    for key in KEYS:
        folder=root/key;folder.mkdir();prior=source/key;frozen=source_plan['arms'][key]
        shutil.copytree(prior/'sdk',folder/'sdk');shutil.copytree(prior/'client',folder/'client')
        shutil.copyfile(build.HERE/'HumanObservation.swift',folder/'client/HumanObservation.swift')
        current=s.tree(folder/'client');changed={n for n in set(current)|set(frozen['client']) if current.get(n)!=frozen['client'].get(n)}
        s.require(changed=={'HumanObservation.swift'},'refresh changed fixture behavior/project')
        plan['arms'][key]={**frozen,'client':current,'original_receipt':sessions.reference(prior/'build-result.json',s)}
    s.save(root/'refresh-plan.json',plan,exclusive=True);verify(root)
    return plan


def verify(root):
    plan=s.read(root/'refresh-plan.json');source=Path(plan['original']);original(source)
    s.require(plan['kind']=='PASSIVE_CLEANUP_OBSERVER_REFRESH' and plan['keys']==KEYS and plan['native_launches']==0,'refresh scope changed')
    s.require(plan['original_plan']==sessions.reference(source/'build-plan.json',s)
        and plan['original_runtime']==sessions.reference(source/'runtime/runtime-plan.json',s),'original fixture pins changed')
    s.require(plan['observer_sha256']==s.sha(build.HERE/'HumanObservation.swift')
        and plan['protected']=={p:s.protected()[p] for p in sessions.PROTECTED}
        and all(s.sha(s.REPO/p)==h for p,h in plan['helpers'].items()),'refresh source/workspace changed')
    source_plan=s.read(source/'build-plan.json')
    s.require(set(plan['arms'])==set(KEYS) and plan['toolchains']==source_plan['toolchains'],'refresh compiler/arm inventory changed')
    for key,arm in plan['arms'].items():
        expected=source_plan['arms'][key]
        s.require(all(arm[k]==expected[k] for k in ['revision','sdk_version','bundle_prefix','sdk','archive_sha256'])
            and arm['original_receipt']==sessions.reference(source/key/'build-result.json',s),'source/compiler identity changed')
        s.require(s.tree(root/key/'sdk')==arm['sdk'] and s.tree(root/key/'client')==arm['client'],'refresh input changed')
        s.require({n for n in arm['client'] if arm['client'].get(n)!=expected['client'].get(n)}=={'HumanObservation.swift'}
            and set(arm['client'])==set(expected['client']) and arm['client']['HumanObservation.swift']==plan['observer_sha256'],
            'refresh altered non-observer source')
    return plan


def compile_pair(root,key):
    plan=verify(root);s.require(key in KEYS,'unadmitted refresh compiler pair');arm=plan['arms'][key];folder=root/key
    started=time.time();deadline=started+build.BUILD_SECONDS
    s.save(folder/'build-admission.json',dict(started_at=started,deadline=deadline,plan_sha256=s.sha(root/'refresh-plan.json')),exclusive=True)
    actual=subprocess.run(['xcodebuild','-version'],env=build.env(arm['sdk_version']),capture_output=True,text=True,check=True,timeout=30).stdout.strip()
    s.require(actual==plan['toolchains'][arm['sdk_version']]['version'],'original compiler unavailable or changed')
    build.command(['xcodebuild','build','-project','AutomaticCoverage.xcodeproj','-scheme','Coverage','-configuration','Release',
        '-destination','generic/platform=iOS Simulator','-derivedDataPath',str(folder/'DerivedData'),'CODE_SIGNING_ALLOWED=NO',
        'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','-jobs','4','-quiet'],folder,'build',arm['sdk_version'],deadline,cwd=folder/'client')
    products={}
    for framework in ['UIKit','SwiftUI']:
        app=folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Fixture.app')
        info=plistlib.loads((app/'Info.plist').read_bytes())
        s.require(info['DTSDKName']=='iphonesimulator'+arm['sdk_version'] and info['MinimumOSVersion']=='16.0'
            and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,'refresh SDK/manifest changed')
        products[framework]=dict(path=str(app),bundle=info['CFBundleIdentifier'],product=s.product(app,bundle=arm['bundle_prefix']+'.'+framework.lower()),declared_multiple_scenes=False)
    result=dict(state='QUALIFIED_BUILD_ONLY',key=key,source=arm['revision'],plan_sha256=s.sha(root/'refresh-plan.json'),
        compiler=build.compiled(folder,arm),products=products,finished_at=time.time(),native_launches=0)
    verify(root);s.require(time.time()<deadline,'refresh build exceeded original clock')
    s.save(folder/'build-result.json',result,exclusive=True);return result


def products(root):
    plan=verify(root);result={}
    for key in KEYS:
        folder=root/key;built=s.read(folder/'build-result.json');admission=s.read(folder/'build-admission.json');arm=plan['arms'][key]
        s.require(built['state']=='QUALIFIED_BUILD_ONLY' and built['key']==key and built['source']==arm['revision']
            and built['plan_sha256']==admission['plan_sha256']==s.sha(root/'refresh-plan.json')
            and admission['started_at']<built['finished_at']<admission['deadline']
            and built['compiler']==build.compiled(folder,arm),'unqualified refreshed compiler output')
        s.require(set(built['products'])=={'UIKit','SwiftUI'},'refresh product inventory changed')
        for framework,value in built['products'].items():
            s.require(s.product(value['path'],bundle=value['bundle'])==value['product'],'refreshed product changed')
            result[key+'-'+framework+'-single']=value
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','build','verify']);parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--original',type=Path);parser.add_argument('--key',choices=KEYS);args=parser.parse_args();root=args.root.resolve()
    if args.action=='prepare':s.require(args.original is not None,'original build root required');prepare(root,args.original.resolve())
    elif args.action=='build':compile_pair(root,args.key)
    else:verify(root)
    print(json.dumps(dict(state='FIXTURE_PREPARATION_ONLY',root=str(root),native_launches=0)))

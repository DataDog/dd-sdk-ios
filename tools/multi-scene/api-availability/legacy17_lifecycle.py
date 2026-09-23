#!/usr/bin/env python3
"""Finish only the four legacy lifecycle cells after activation-boundary repair."""
import argparse
import copy
import hashlib
from pathlib import Path
import time

import legacy17 as base

shared=base.shared
require=base.require
DEFINITION=shared.REPO/'DatadogRUM/MultiSceneSupport/Results/EXP-225-legacy17-lifecycle-definition.json'
ORIGINAL_PROJECTION=base.legacy.observed_lifecycle_source


def lifecycle_source(source):
    source=ORIGINAL_PROJECTION(source)
    initial='            marker("BeforeBackground")'
    resumed='            try? await Task.sleep(nanoseconds: 500_000_000)'
    require(source.count(initial)==source.count(resumed)==1,'lifecycle activation anchors changed')
    def wait(count):
        return '''            if !(await waitFor {
                UIApplication.shared.applicationState == .active && EventStore.shared.snapshot().filter {
                    $0["type"] as? String == "lifecycle" && $0["name"] as? String == UIApplication.didBecomeActiveNotification.rawValue
                }.count == COUNT
            }) { failures.append("actual activation COUNT missing") }
'''.replace('COUNT',str(count))
    return source.replace(initial,wait(1)+initial).replace(resumed,wait(2).rstrip())


def activated_ready(value,run_id):
    base.legacy.check_ready(value,run_id)
    events=value['events'];notifications=[(i,r['name']) for i,r in enumerate(events) if r['type']=='lifecycle']
    require([n for _,n in notifications]==[base.legacy.ACTIVE],'initial actual activation missing')
    require(all(notifications[0][0]<i for i,r in enumerate(events) if r['type'] in ['action','resource']),'marker before initial activation')


def navigation_cases(prior):
    require(prior['status']=='INVALID' and prior['final_cleanup']=='PASS','prior cleanup/status does not admit reuse')
    selected=[c for c in prior['cases'] if c['mode'] in ['automatic','manual']]
    require(len(selected)==4 and {(c['arm'],c['mode']) for c in selected}=={(a,m) for a in base.legacy.ARMS for m in ['automatic','manual']},'incomplete navigation reuse')
    require(all(c['status']==c['scenario']==c['evidence']==c['cleanup']['status']=='PASS' for c in selected),'navigation was not accepted')
    other=[c for c in prior['cases'] if c not in selected]
    require(len(other)==1 and other[0]['arm']=='baseline' and other[0]['mode']=='lifecycle-automatic' and other[0]['status']=='INVALID' and other[0].get('error')=='markers straddle the wrong lifecycle boundary','different native failure requires separate admission')
    require(len({c['run_id'] for c in selected})==4,'duplicate reused run')
    return copy.deepcopy(selected)


class Runner(base.Runner):
    def __init__(self,root,navigation_root):
        self.navigation_root=Path(navigation_root).resolve();self.navigation=None
        base.OWNER=DEFINITION
        base.HELPERS += ['tools/multi-scene/api-availability/'+n for n in ['legacy17_lifecycle.py','test_legacy17_lifecycle.py']]+[str(DEFINITION.relative_to(shared.REPO))]
        super().__init__(root)

    def preflight(self):
        base.legacy.observed_lifecycle_source=lifecycle_source
        try:super().preflight()
        finally:base.legacy.observed_lifecycle_source=ORIGINAL_PROJECTION
        prior=shared.read(self.navigation_root/'summary.json');selected=navigation_cases(prior)
        require(prior['source_revisions']==self.summary['source_revisions'],'reused navigation source differs')
        frozen=shared.read(self.navigation_root/'frozen-inputs.json');require(frozen['protected']==self.protected,'protected files changed since navigation')
        old_builds=Path(prior['reused_preparation']['root'])/'builds'
        for arm in base.legacy.ARMS:
            require(self.frozen[arm]['sdk']==frozen['arms'][arm]['sdk'] and self.frozen[arm]['fixture']['Sources']==frozen['arms'][arm]['fixture']['Sources'],'navigation source/fixture differs')
        immutable=[self.navigation_root/'summary.json',self.navigation_root/'frozen-inputs.json']
        immutable += [Path(row[k]) for row in prior['commands'] for k in ['stdout','stderr']]
        immutable += [Path(c['result']['path']) for c in selected]
        self.navigation=dict(root=str(self.navigation_root),build_root=str(old_builds),frozen=frozen,builds={k:v for k,v in prior['builds'].items() if k.endswith('/Navigation')},
                             immutable_files={str(p):shared.sha(p) for p in immutable},earlier_immutable_files=prior['reused_preparation']['immutable_files'])
        self.summary['reused_navigation']=self.navigation
        for case in selected:case['reused_from']=str(self.navigation_root/'summary.json')
        self.summary['cases']=selected;self.verify_inputs();self.verify_evidence()
        shared.save(self.root/'navigation-reuse.json',dict(cases=selected,binding=self.navigation),exclusive=True);self.save()
        require(time.time()<self.deadline,'late navigation qualification')

    def verify_inputs(self):
        super().verify_inputs()
        if not self.navigation:return
        item=self.navigation
        for key in ['immutable_files','earlier_immutable_files']:
            require(all(shared.sha(p)==v for p,v in item[key].items()),'reused summary/log/result changed')
        for arm,bound in item['frozen']['arms'].items():
            folder=Path(item['build_root'])/arm
            require(shared.tree(folder/'sdk')==bound['sdk'] and shared.tree(folder/'Sources')==bound['fixture']['Sources'],'reused navigation inputs changed')
        for key,record in item['builds'].items():
            folder=Path(item['build_root'])/key.split('/')[0]
            require(shared.product(record['app'],record['bundle'])==record['full_product'],'reused product changed')
            for rel,row in record['compiler_lists'].items():
                require(shared.sha(folder/rel)==row['sha256'] and all(shared.sha(p)==v for p,v in row['members'].items()),'reused compiler membership changed')
            require(all(shared.sha(folder/n)==v for n,v in record['compiled_objects'].items()),'reused object changed')

    def wait_json(self,path,launched_ns,timeout=45):
        value=super().wait_json(path,launched_ns,timeout)
        if path.name=='ready.json':activated_ready(value,self.summary['cases'][-1]['run_id'])
        return value

    def execute(self):
        try:
            self.preflight();self.build('baseline','Lifecycle');self.run_case('baseline','17.5','lifecycle-automatic')
            self.summary['lifecycle_readiness']='PASS';self.build('candidate','Lifecycle')
            for item in self.definition['matrix']:
                if (item['arm'],item['mode'])!=('baseline','lifecycle-automatic'):self.run_case(item['arm'],'17.5',item['mode'])
            self.verify_inputs();self.verify_products();self.verify_evidence()
            require(time.time()<self.summary['stage_deadline'],'final evidence after stage deadline')
            self.summary['status']=base.matrix(self.summary['cases'])
        except Exception as error:self.summary['status']='INVALID';self.summary['error']=str(error)
        finally:self.finish()
        return self.summary['status']=='PASS'


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--accepted-navigation',type=Path,required=True);args=p.parse_args()
    raise SystemExit(0 if Runner(args.root,args.accepted_navigation).execute() else 1)

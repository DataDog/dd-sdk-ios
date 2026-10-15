"""Collect once, then grade saved default-Off Monitor evidence without native retries.

Exports use the exact frozen cell transport. Source, compiler and artifact faults
are reported together; a compiler/parser failure grants no SDK regression verdict.
"""
import ast
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import struct
import sys
import time

import default_off as oracle
import default_off_attachments as attachments
import default_off_transport as transport


XC = '/Applications/Xcode_27.1.app/Contents/Developer/usr/bin/xcresulttool'
TARGETS = ['DatadogInternal', 'DatadogCore', 'DatadogRUM', 'TestUtilities', 'DatadogRUMTests']


def ref(path):
    path = Path(path)
    return dict(path=str(path.resolve()), sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def load(binding):
    path = Path(binding['path'])
    assert not path.is_symlink() and ref(path) == binding, 'consumed binding changed'
    return json.loads(path.read_bytes())


def write(path, value, join=lambda:None):
    return transport.publish(path,value,join)


def classify(summary, tree, selected, device):
    """Roster and actual device decide; durations and benign warnings are retained."""
    assert type(summary) is dict and summary, 'required summary object'
    assert type(tree) is dict and tree, 'required test tree object'
    assert type(selected) is list and type(device) is dict
    assert type(tree.get('testNodes')) is list and tree['testNodes'], 'required native nodes'
    count = len(selected)
    assert count and len(set(selected)) == count
    assert summary['result'] == 'Passed' and summary['totalTestCount'] == summary['passedTests'] == count
    assert summary['failedTests'] == summary['skippedTests'] == summary['expectedFailures'] == 0
    assert summary['testFailures'] == []
    dc = summary['devicesAndConfigurations']; assert len(dc) == 1
    actual = dc[0]['device']
    for key, expected in dict(deviceId=device['udid'], deviceName=device['name'], osVersion=device['os'], architecture='arm64', platform='iOS Simulator').items():
        assert actual[key] == expected, 'native device differs: ' + key
    assert tree['devices'] == [actual]
    assert dc[0]['passedTests'] == count and dc[0]['failedTests'] == dc[0]['skippedTests'] == dc[0]['expectedFailures'] == 0
    nodes = []
    def walk(node):
        assert type(node) is dict and node, 'native node object'
        assert type(node.get('children', [])) is list, 'native node children'
        if node.get('nodeType') == 'Test Case': nodes.append(node)
        for child in node.get('children', []): walk(child)
    for node in tree['testNodes']: walk(node)
    observed = ['DatadogRUMTests/' + n['nodeIdentifier'] for n in nodes]
    assert len(observed) == len(set(observed)) == count and set(observed) == set(selected), 'exact native roster differs'
    assert all(n['result'] == 'Passed' and not n.get('children') for n in nodes), 'failed/repeated native case'
    return nodes


def proposal(root):
    """Validate executable trust independently of runtime completion/stop state."""
    d = attachments.decode((root/'definition.json').read_bytes())
    review = attachments.decode((root/'review.json').read_bytes())
    assert type(d) is dict and d and type(review) is dict and review
    assert ref(root/'definition.json') in review['definitions'] and ref(root/'controller.py') in review['controllers']
    assert review['verdict'] == 'PASS_COMPONENT_QUALIFICATION_PROPOSAL_ONLY' and review['reviewer'] == '/root/rum_runtime_reviewer'
    assert type(d['consumer_bindings']) is dict
    for binding in d['consumer_bindings'].values(): load_bytes(binding)
    return d


def authority(root):
    d = proposal(root)
    if (root/'controller-stop.json').exists():raise ValueError('sticky controller stop forbids acceptance or export')
    completion=attachments.decode((root/'completion.json').read_bytes())
    a = json.loads((root/'admission.json').read_bytes()); out = json.loads((root/'native-qualification-outcome.json').read_bytes()); cleanup = json.loads((root/'cleanup.json').read_bytes())
    start = load(out['start'])
    assert a['definition'] == ref(root/'definition.json') and a['review'] == ref(root/'review.json') and a['controller'] == ref(root/'controller.py') == d['controller']
    assert a['controller_pid'] == a['controller_pgid'] == start['controller_pid']
    assert start['pid'] == start['pgid'] and start['command'] == d['command']
    assert start['deadline'] == a['deadline'] == a['started_at'] + 660
    assert start['cleanup_cutoff'] == a['cleanup_deadline'] == a['deadline'] + 180 < d['operational_window_cutoff']
    assert not out['timed_out'] and out['exception_type'] is None and out['owned_group_absent'] and out['completed_at'] < a['cleanup_deadline']
    assert cleanup['admission'] == ref(root/'admission.json') and cleanup['process_outcome'] == ref(root/'native-qualification-outcome.json') and cleanup['child'] == out['start']
    assert cleanup['state'] == 'PASS_COMPONENT_LANE_RESTORATION_ONLY' and cleanup['original_state_restored'] and cleanup['selected_device_state'] == 'Shutdown' and cleanup['completed_at'] < a['cleanup_deadline']
    assert a['original_device']['udid'] == d['device']['udid'] and a['original_device']['state'] == 'Shutdown'
    assert completion['state']=='CONTROLLER_RETURNED_AFTER_OWNER_PUBLICATION' and completion['definition']==ref(root/'definition.json') and completion['review']==ref(root/'review.json') and completion['controller']==ref(root/'controller.py')
    for key,name in [('admission','admission.json'),('outcome','native-qualification-outcome.json'),('cleanup','cleanup.json')]:assert completion[key]==ref(root/name)
    assert completion['child']==out['start'] and completion['completed_at']<d['operational_window_cutoff']
    issued=completion['issued_owner']
    assert issued['state']=='COMPONENT_TESTS_RETURNED_REQUIRES_RECONCILIATION' and issued['definition']==completion['definition'] and issued['review']==completion['review'] and issued['controller']==completion['controller']
    assert all(issued[k]==completion[k] for k in ['admission','child','outcome','cleanup']) and issued['controller_pid']==a['controller_pid']
    return d, out


def load_bytes(binding):
    path=Path(binding['path']); raw=path.read_bytes()
    assert not path.is_symlink() and hashlib.sha256(raw).hexdigest() == binding['sha256'], str(path)
    return raw


def helper(d):
    namespace = dict(__name__='bound_saved_helper', __file__=d['saved_helper']['path'])
    exec(compile(load_bytes(d['saved_helper']), namespace['__file__'], 'exec'), namespace)
    return namespace


def source(d):
    frozen = load(d['source_freeze']); raw=load_bytes(d['source_verifier'])
    namespace=dict(__name__='bound_source_verifier')
    exec(compile(raw,d['source_verifier']['path'],'exec'),namespace)
    namespace['verify'](d['cwd'], d['source_head'], frozen)
    return frozen


def collect(root):
    """One actual export; missing successful completion forbids all dispatch."""
    transport.checked_environment(os.environ)
    transport.install_termination_handlers()
    d,out=authority(root)
    if out['returncode']!=0:raise ValueError('native command failed; only saved diagnostics allowed')
    source(d);h=helper(d)
    if time.time()+240>=d['operational_window_cutoff']:raise ValueError('original export reservation unavailable')
    bindings={name:ref(root/name) for name in ['definition.json','review.json','controller.py','completion.json','admission.json','native-qualification-outcome.json','cleanup.json']}
    result=root/'actual-result.xcresult';initial=h['members'](result)
    clone=root/'result-export-input.xcresult'
    if os.path.lexists(clone):raise ValueError('consumed export namespace')
    shutil.copytree(result,clone,symlinks=True)
    assert h['members'](clone)==initial
    products=h['products'](root,TARGETS)
    folder=root/'actual-attachments'
    if os.path.lexists(folder):raise ValueError('consumed attachment namespace')
    folder.mkdir()
    exports={};issues=[]
    def join():
        authority(root);source(d)
        assert all(ref(root/name)==binding for name,binding in bindings.items())
        assert h['members'](result)==initial and h['products'](root,TARGETS)==products
    commands={kind:[XC,'get','test-results',kind,'--path',str(clone)] for kind in ('summary','tests')}
    commands['attachments']=[XC,'export','attachments','--schema-version','0.4.0','--path',str(clone),'--output-path',str(folder)]
    for kind,command in commands.items():
        join();now=time.time();deadline=now+60;cutoff=deadline+10
        if cutoff>=d['operational_window_cutoff']:raise ValueError('original export cutoff')
        rc,_,issued,_,absent=transport.process(root,Path(d['cwd']),dict(os.environ,DEVELOPER_DIR='/Applications/Xcode_27.1.app/Contents/Developer'),command,'actual-'+kind,deadline,cutoff,join)
        exports[kind]=issued;observed=load(issued)
        if observed['exception_type'] in ('KeyboardInterrupt','SystemExit') or not absent:raise RuntimeError('interrupted export stopped safely')
        if rc!=0 or observed['exception_type'] is not None:issues.append(dict(kind=kind,outcome=issued))
    after=h['members'](clone);h['clone_payload_join'](initial,after,clone)
    sealed=h['members'](folder)
    def final_join():
        join();assert h['members'](clone)==after and h['members'](folder)==sealed
        assert all(ref(Path(v['path']))==v for v in exports.values())
    return write(root/'collection.json',dict(state='SAVED_EXPORTS_ONLY' if not issues else 'SAVED_EXPORTS_INCOMPLETE',definition=ref(root/'definition.json'),exports=exports,
        native_result=initial,export_copy=after,products=products,attachments=sealed,issues=issues,consumer=ref(__file__),completed_at=time.time(),gates_closed=[]),final_join)


def grade(root):
    """Permission to export is separate from read-only diagnostic inspection."""
    report=dict(state='INCOMPLETE',issues=[],gates_closed=[],consumer=ref(__file__))
    def inspect(phase,fn):
        try:return fn()
        except (AssertionError,ValueError,KeyError,TypeError,IndexError,OSError,struct.error,StopIteration,RuntimeError,AttributeError) as e:
            report['issues'].append(dict(phase=phase,detail=str(e) or type(e).__name__))
    report['definition']=inspect('definition-binding',lambda:ref(root/'definition.json'))
    inspect('definition',lambda:attachments.decode((root/'definition.json').read_bytes()))
    trusted=inspect('proposal-code-trust',lambda:proposal(root))
    d=trusted if trusted is not None else {}
    inspect('authority',lambda:authority(root))
    out=inspect('native-outcome',lambda:attachments.decode((root/'native-qualification-outcome.json').read_bytes())) or {}
    frozen=inspect('source',lambda:source(d)) if trusted is not None else None
    h=inspect('saved-helper',lambda:helper(d)) if trusted is not None else None
    expected=(inspect('expected-source-lists',lambda:load(d['expected_source_lists'])) or {}) if trusted is not None else {}
    others=(inspect('other-source-lists',lambda:load(d['other_sources'])) or {}) if trusted is not None else {}
    rawout=inspect('native-stdout',lambda:load_bytes(out['stdout']))
    inspect('native-stderr',lambda:load_bytes(out['stderr']))
    lines=rawout.decode(errors='replace').splitlines() if rawout is not None else []
    inspect('native-result',lambda:require(out.get('returncode')==0 and out.get('exception_type') is None))
    byname={r['path']:r.get('sha256') for r in frozen['files']} if frozen else {}
    inventories=[];products=[];compilers={};other_compilations=[]
    for target in TARGETS:
        rows=inspect('source-files:'+target,lambda t=target:h['file_inventory'](root,Path(d['cwd']),{t:expected[t]})) if h else None
        if rows:inventories+=rows
        if frozen:inspect('expected-binding:'+target,lambda t=target:require(all(byname[r['path']]==r['sha256'] for r in expected[t])))
        def compiler(t=target,actual_rows=rows):
            drivers=[]
            for line in lines:
                if 'swiftc -module-name '+t+' ' not in line:continue
                tokens=shlex.split(line.strip());index=next(i for i,x in enumerate(tokens) if x.endswith('/swiftc'));tokens=tokens[index:]
                assert tokens[tokens.index('-module-name')+1]==t
                for flag,value in [('-target','arm64-apple-ios15.0-simulator'),('-swift-version','5')]:
                    assert tokens.count(flag)==1 and tokens[tokens.index(flag)+1]==value,t+': '+flag
                assert '-Onone' in tokens and '-enable-testing' in tokens
                assert h['has_testing_define'](line),t+': testing define'
                assert tokens[0]=='/Applications/Xcode_27.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'
                assert tokens[tokens.index('-sdk')+1]==d['compiler_sdk']
                assert actual_rows and [x[1:] for x in tokens if x.startswith('@')]==[actual_rows[0]['list']['path']]
                drivers.append(line)
            assert drivers,'missing compiler driver'
            return drivers
        compilers[target]=inspect('compiler:'+target,compiler)
        actual=inspect('C-ObjC-link:'+target,lambda t=target:h['other_compilation'](root,Path(d['cwd']),lines,{t:others[t]},require_versions=True)) if h else None
        if actual:other_compilations+=actual
        actual=inspect('products:'+target,lambda t=target:require(h is not None) or h['products'](root,[t]))
        if actual:products+=actual
        def product_identity(t=target):
            p=root/'derived-data/Build/Products/Debug-iphonesimulator'/(t+('.xctest' if t.endswith('Tests') else '.framework'))
            raw=(p/t).read_bytes();info=plistlib.loads((p/'Info.plist').read_bytes())
            assert struct.unpack('<II',raw[:8])==(0xfeedfacf,0x100000c) and info['CFBundleExecutable']==t
        inspect('architecture:'+target,product_identity)
    report.update(compiler_drivers=compilers,source_lists=inventories,other_compilations=other_compilations,products=products)
    collection=inspect('collection',lambda:attachments.decode((root/'collection.json').read_bytes()))
    def collection_schema():
        required={'state','definition','exports','native_result','export_copy','products','attachments','issues','consumer','completed_at','gates_closed'}
        assert type(collection) is dict and set(collection)==required, 'required complete collection schema'
        assert collection['state']=='SAVED_EXPORTS_ONLY' and collection['issues']==[] and collection['gates_closed']==[]
        assert type(collection['exports']) is dict and set(collection['exports'])=={'summary','tests','attachments'}
        assert all(type(collection[k]) is list and collection[k] for k in ['native_result','export_copy','products','attachments']), 'required nonempty collection inventories'
    inspect('collection-schema',collection_schema)
    inspect('native-result-members',lambda:require(h is not None) or h['members'](root/'actual-result.xcresult'))
    inspect('export-copy-members',lambda:require(h is not None) or h['members'](root/'result-export-input.xcresult'))
    if type(collection) is dict:
        def custody():
            assert collection['state']=='SAVED_EXPORTS_ONLY' and collection['definition']==ref(root/'definition.json') and collection['consumer']==ref(__file__)
            assert collection['native_result']==h['members'](root/'actual-result.xcresult') and collection['export_copy']==h['members'](root/'result-export-input.xcresult')
            assert collection['products']==products and collection['attachments']==h['members'](root/'actual-attachments')
        inspect('collection-custody',custody)
    exported={}
    for kind in ['summary','tests','attachments']:
        def export(k=kind):
            binding=collection['exports'][k] if type(collection) is dict and type(collection.get('exports')) is dict and k in collection['exports'] else ref(root/('actual-'+k+'-outcome.json'))
            value=load(binding);start=load(value['start']);path=str(root/'result-export-input.xcresult');folder=str(root/'actual-attachments')
            expected_command=([XC,'export','attachments','--schema-version','0.4.0','--path',path,'--output-path',folder] if k=='attachments' else [XC,'get','test-results',k,'--path',path])
            assert start['command']==expected_command and value['command']==expected_command
            assert value['returncode']==0 and value['exception_type'] is None and not value['timed_out'] and value['owned_group_absent']
            assert start['pid']==start['pgid'] and value['completed_at']<start['cleanup_cutoff']<d['operational_window_cutoff']
            load_bytes(value['stderr']);raw=load_bytes(value['stdout'])
            return attachments.decode(raw) if k!='attachments' else True
        exported[kind]=inspect('export:'+kind,export)
        # Retain raw failed/stopped case observations even when their custody failed.
        if kind!='attachments' and exported[kind] is None:
            diagnostic=inspect('saved-diagnostic:'+kind,lambda k=kind:attachments.decode((root/('actual-'+k+'.stdout')).read_bytes()))
            report['unqualified_'+kind]=diagnostic
    summary=exported.get('summary');tree=exported.get('tests')
    if type(tree) is dict:
        report['native_case_observations']=tree.get('testNodes')
    elif type(report.get('unqualified_tests')) is dict:
        report['native_case_observations']=report['unqualified_tests'].get('testNodes')
    nodes=inspect('native-roster',lambda:classify(summary,tree,d['expected_source_tests'],d['device']))
    if type(summary) is dict:report['runtime_warnings']=summary.get('runtimeWarnings')
    manifest=inspect('attachment-manifest',lambda:attachments.decode((root/'actual-attachments/manifest.json').read_bytes()))
    inspect('manifest-inventory',lambda:require(type(manifest) is list and len(manifest)==len(attachments.METHOD_SCENARIOS)))
    if nodes is not None:
        identities={n['nodeIdentifier']:n['name'].removesuffix('()') for n in nodes}
        parsed=attachments.collect(root/'actual-attachments',manifest,d['device']['udid'],identities);report['attachments']=parsed
        if parsed['state']!='PASS_ATTACHMENT_INVENTORY_ONLY':report['issues'].append(dict(phase='attachments',detail=parsed.get('faults')))
        for row in parsed.get('records',[]):inspect('scenario:'+row['trace']['scenario'],lambda r=row:oracle.validate_monitor(r['trace'],d['revision']))
        if type(collection) is dict:inspect('attachment-file-inventory',lambda:require({r['path'] for r in collection['attachments']}=={'manifest.json'}|{a['exportedFileName'] for c in manifest for a in c['attachments']}))
    if trusted is not None:inspect('terminal-source',lambda:source(d))
    if type(collection) is dict and h:
        inspect('terminal-custody',lambda:require(collection['native_result']==h['members'](root/'actual-result.xcresult') and collection['export_copy']==h['members'](root/'result-export-input.xcresult') and collection['products']==h['products'](root,TARGETS) and collection['attachments']==h['members'](root/'actual-attachments')))
    if not report['issues']:report['state']='PASS_DEFAULT_OFF_MONITOR_CELL_ONLY'
    return report


def require(value):
    assert value


if __name__=='__main__':
    mode,folder=sys.argv[1:];root=Path(folder).resolve()
    if mode=='collect':print(json.dumps(collect(root)))
    elif mode=='grade':
        report=grade(root)
        print(json.dumps(write(root/'qualification.json',report,lambda:require(grade(root)==report))))
    else:raise ValueError('collect or grade required')

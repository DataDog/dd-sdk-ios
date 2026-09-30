"""Compose the actual capture store and transport around synthetic mapper rows."""
import copy
import base64
import hashlib
import json
from pathlib import Path
import shutil

from acceptance_common import require
import scene_background_channel as channel
import scene_background_cycle as cycle
from test_scene_background_cycle import fixture, RUN
from scene_background_fixture import sha

HERE = Path(__file__).resolve().parent


def prepare(destination):
    destination = Path(destination)
    require(destination.is_absolute() and destination.resolve() == destination and not destination.exists(),
            'fresh composition control directory required')
    original = fixture()
    result = cycle.validate_local(original, RUN, profile=cycle.PROFILE)
    cases = []

    def add(name, mode='ordinary', change=None, accept=False):
        value = dict(name=name, mode=mode, initial=copy.deepcopy(original), fresh=copy.deepcopy(original),
                     result=copy.deepcopy(result), accept=accept,
                     witness=json.loads(next(row['reason'] for row in reversed(original)
                                             if row.get('name','').startswith('h10.after.'))))
        if change: change(value)
        cases.append(value)

    def tail(value, row):
        row = copy.deepcopy(row)
        row.update(sequence=len(value['fresh'])+1)
        value['fresh'].append(row)

    def view_tail(value, *, view='B-current', active=True, version=5):
        row = next(r for r in value['fresh'] if r['kind']=='rum-view-snapshot' and r['rumContext']['viewID']==view)
        row = copy.deepcopy(row)
        row['rumContext'].update(viewActive=active, viewDocumentVersion=version)
        tail(value,row)

    add('complete-sealed-prefix', accept=True)
    add('ordinary-native-tail', change=lambda v:tail(v,dict(schemaVersion=5,runID=RUN,scenarioID=cycle.SCENARIO,
        kind='scene-geometry',evidenceSource='probe',geometry=dict(x=0,y=0,width=597.3333333333334,height=701.0))),accept=True)
    add('delayed-view-revision',change=view_tail,accept=True)
    add('out-of-order-view-revision',change=lambda v:view_tail(v,version=3),accept=True)
    add('extra-action',change=lambda v:tail(v,next(r for r in v['fresh'] if r['kind']=='rum-action')))
    add('extra-resource',change=lambda v:tail(v,next(r for r in v['fresh'] if r['kind']=='rum-resource')))
    add('late-error',change=lambda v:tail(v,dict(schemaVersion=5,runID=RUN,scenarioID=cycle.SCENARIO,
                                               kind='rum-error',evidenceSource='rum-mapper')))
    add('peer-view-ended',change=lambda v:view_tail(v,active=False))
    add('original-view-reactivated',change=lambda v:view_tail(v,view='A-current',version=3))
    def new_view(v):
        view_tail(v);v['fresh'][-1]['rumContext']['viewID']='foreign-view'
    add('new-view-in-extension',change=new_view)
    add('duplicate-view-document',change=lambda v:view_tail(v,version=4))
    add('truncated-prefix',change=lambda v:v['fresh'].pop())
    add('rewritten-prefix',change=lambda v:v['fresh'][0]['rumContext'].update(viewName='rewritten'))
    add('sequence-gap',change=lambda v:v['fresh'][-1].update(sequence=999))
    add('foreign-run',change=lambda v:v['fresh'][-1].update(runID='foreign'))
    add('terminal-before-inspection','terminal-before')
    add('terminal-during-seal','terminal-after')
    add('non-pass-oracle',change=lambda v:v['result'].update(state='INCONCLUSIVE'))
    add('wrong-oracle-source','wrong-oracle')
    add('wrong-capture-reference','wrong-capture')
    add('wrong-display-reference','wrong-display')
    add('wrong-consumed-phase','wrong-consumed')
    add('wrong-final-invocation','wrong-invocation')
    add('wrong-work-owner',change=lambda v:v['result']['work'][0].update(view_id='foreign'))
    add('stop-before-seal','stop')
    add('execution-cutoff','cutoff')
    add('cutoff-during-seal-publication','cutoff-after-seal')
    add('native-before-rejected','native-before')
    add('native-after-rejected','native-after')
    add('changed-capture-bytes','changed-capture')
    add('symlink-capture','symlink-capture')
    add('unknown-staged-command','unknown-command')
    add('mutated-consumed-phase','mutated-phase')
    add('reply-collision-after-seal','reply-collision')
    add('collection-before-third-consume','premature-collection')
    add('zero-final-invocation','zero-invocation')
    add('seal-without-inspect','missing-inspection')
    add('duplicate-seal','duplicate-seal',accept=True)
    add('cleanup-tail-kept-separately','cleanup-tail',accept=True)
    destination.mkdir()
    (destination/'control.swift').write_text(channel.source())
    (destination/'controls.json').write_text(json.dumps(cases,indent=2)+'\n')
    files=[HERE/n for n in ['scene_background_capture.swift','scene_background_phase.swift',
        'scene_background_channel.py','focus_activation_channel.swift','scene_background_cycle.py',
        'scene_background_session_checks.py','scene_background_session_check_main.swift','test_scene_background_cycle.py']]
    receipt=dict(state='SYNTHETIC_CAPTURE_TRANSPORT_CONTROLS',controls=len(cases),source={str(p):sha(p) for p in files},
                 output={p.name:sha(p) for p in destination.iterdir()},native_runs=0,gates_closed=[],
                 scope='Actual capture store and phase filesystem protocol; SDK, UIKit and app driver do not execute')
    (destination/'preparation.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return receipt


def verify_host(execution_root, destination):
    """Mutate copied synthetic artifacts, never the original native/evidence files."""
    import scene_background_capture as capture
    source = Path(execution_root)/'complete-sealed-prefix/channel'
    destination = Path(destination)
    require(source.is_dir() and destination.is_absolute() and not destination.exists(), 'fresh host control output required')
    destination.mkdir()
    identity = json.loads((source/'challenge.json').read_text())
    challenge = json.loads((source/'collection/challenge.json').read_text())
    oracle_sha = sha(Path(cycle.__file__))
    cases = ['unchanged','wrong-identity','changed-seal-bytes','wrong-oracle-source','wrong-phase-proof',
             'changed-semantic-result','missing-capture','symlink-capture','foreign-prefix','terminal-mutated',
             'missing-extension','extra-critical-work','rewritten-native-journal','boolean-sequence',
             'wrong-final-invocation','boolean-final-invocation']
    results = []

    def encode(value): return json.dumps(value,sort_keys=True,separators=(',',':')).encode()
    def bytes64(value): return base64.b64encode(encode(value)).decode()
    def put(directory,label,value):
        raw=encode(value);digest=hashlib.sha256(raw).hexdigest();name=label+'-'+digest+'.json'
        path=directory/name
        if path.exists(): require(path.read_bytes()==raw,'control artifact collision')
        else:path.write_bytes(raw)
        return dict(name=name,sha256=digest,bytes=len(raw))

    for name in cases:
        folder=destination/name;shutil.copytree(source/'evidence',folder)
        original=next(folder.glob('seal-*.json'));seal=json.loads(original.read_text())
        expected=copy.deepcopy(identity)
        expected_challenge=copy.deepcopy(challenge)
        if name=='wrong-identity': expected['processID']+=1
        if name=='wrong-phase-proof':seal['challenge']['consumedPhaseReplies'].pop()
        if name in ['wrong-final-invocation','boolean-final-invocation']:
            expected_challenge['finalInvocationSequence'] = True if name=='boolean-final-invocation' else challenge['finalInvocationSequence']+1
            seal['challenge']=copy.deepcopy(expected_challenge)
            proof=json.loads(capture.decode(seal['semanticProof']))
            proof['finalInvocationSequence']=expected_challenge['finalInvocationSequence']
            seal['semanticProof']=bytes64(proof)
        if name in ['wrong-oracle-source','changed-semantic-result']:
            proof=json.loads(capture.decode(seal['semanticProof']))
            if name=='wrong-oracle-source':proof['oracleSourceSHA256']='e'*64
            else:
                result=json.loads(capture.decode(proof['localResult']));result['work'][0]['view_id']='foreign'
                proof['localResult']=bytes64(result)
            seal['semanticProof']=bytes64(proof)
        if name in ['missing-capture','symlink-capture']:
            path=folder/seal['inspected']['name'];retained=destination/(name+'-original.json');path.rename(retained)
            if name=='symlink-capture':path.symlink_to(retained)
        if name in ['foreign-prefix','terminal-mutated','extra-critical-work','rewritten-native-journal','boolean-sequence']:
            fresh=json.loads((folder/seal['fresh']['name']).read_text())
            if name=='terminal-mutated':fresh['snapshot']['terminal']=bytes64(dict(state='PASS'))
            elif name=='rewritten-native-journal':
                native=json.loads(capture.decode(fresh['after']));events=native['snapshot']['continuity']['events']
                events.pop(0)
                for i,row in enumerate(events):row['revision']=i+1
                fresh['after']=bytes64(native)
            else:
                rows=fresh['snapshot']['signals']
                if name=='extra-critical-work':
                    row=next(json.loads(capture.decode(row)) for row in rows if json.loads(capture.decode(row))['kind']=='rum-action')
                    row['sequence']=len(rows)+1;rows.append(bytes64(row))
                    seal['extensionRows']=put(folder,'extension',[rows[-1]])
                    seal['extensionFirstSequence']=seal['extensionLastSequence']=len(rows)
                else:
                    row=json.loads(capture.decode(rows[0]))
                    if name=='foreign-prefix':row['runID']='foreign'
                    else:row['sequence']=True
                    rows[0]=bytes64(row)
            seal['fresh']=put(folder,'capture',fresh)
        if name=='missing-extension':seal['extensionRows']=put(folder,'extension',['e30='])
        reference=put(folder,'seal',seal)
        if name=='changed-seal-bytes':(folder/reference['name']).write_bytes(b'changed')
        failure=None
        try:capture.validate_seal(folder,reference,identity=expected,challenge=expected_challenge,oracle_source_sha256=oracle_sha)
        except Exception as error:failure=type(error).__name__+': '+str(error)
        results.append(dict(name=name,passed=(failure is None)==(name=='unchanged'),failure=failure))
    value=dict(state='PASS' if all(r['passed'] for r in results) else 'FAIL',checks=results,
               source={str(Path(capture.__file__)):sha(capture.__file__),str(Path(__file__)):sha(__file__)},
               native_runs=0,gates_closed=[])
    (destination/'result.json').write_text(json.dumps(value,indent=2)+'\n')
    return value

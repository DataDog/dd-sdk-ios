"""New H10 contract controls with generated media; no device or SDK execution."""
import base64
import copy
import json
from pathlib import Path
import subprocess
import uuid

import operation_display as media
import operation_transport as t
import scene_background_capture as capture
import scene_background_channel as channel
import scene_background_cycle as cycle
import scene_background_display as display
import scene_background_protocol as protocol
from test_scene_background_cycle import fixture, RUN

HERE = Path(__file__).resolve().parent


def encoded(raw): return base64.b64encode(raw).decode()


def save(path, raw):
    path = Path(path); t.save(path, raw)
    return media.reference(path)


def prepare(destination):
    destination = Path(destination)
    t.require(destination.is_absolute() and not destination.exists(), 'fresh display control directory required')
    destination.mkdir(); evidence = destination/'evidence'; evidence.mkdir()
    identity = dict(schemaVersion=1, runID=RUN, processID=4312, scenarioID=cycle.SCENARIO, profile=cycle.PROFILE,
                    sourceRevision='a'*40, installedCodeSHA256='b'*64, challengeID=str(uuid.uuid4()),
                    executionDeadlineMilliseconds=2_000_000_000_000, cleanupDeadlineMilliseconds=2_000_000_060_000)
    rows = fixture(); cases = []; anchors = []; grants = []
    names = ['h10.arm','h10.before.B.while-A-background','h10.before.A.after-foreground','h10.after.B.after-A-foreground']
    for index, name in enumerate(names):
        witness = json.loads(next(row['reason'] for row in rows if row.get('name') == name))
        # Different valid native geometry and foreground focus are intentional.
        witness['snapshot']['scenes'][1]['geometry']['width'] = 597.3333333333334 + index
        raw_witness = t.encode(witness)
        phase = dict(identity=identity, phase=index, name=protocol.PHASES[index], challengeID=str(uuid.uuid4()), maximumInspections=24)
        if index == 3:
            phase.update(consumedPhaseReplies=[ref['sha256'] for ref in grants], finalInvocationSequence=capture.final_invocation(rows))
        request = protocol.request(phase, 1, 'inspect', t.sha(t.encode(phase)))
        cap = dict(identity=identity, sequence=index+1, boundary=phase['name'], before=encoded(raw_witness),
                   after=encoded(raw_witness), snapshot=dict(signals=[encoded(t.encode(row)) for row in (rows if index == 3 else rows[:4])]))
        raw_cap = t.encode(cap); sha = t.sha(raw_cap); cap_name = 'capture-'+sha+'.json'
        save(evidence/cap_name, raw_cap); ref = dict(name=cap_name,sha256=sha,bytes=len(raw_cap))
        sent = t.load(request); observation = t.encode(ref)
        reply = t.encode(dict(challenge=phase,sequence=1,commandID=sent['commandID'],requestSHA256=t.sha(request),
                              operation='inspect',outcome='observed',observation=encoded(observation),observationSHA256=t.sha(observation)))
        anchors.append(dict(request=save(destination/f'request-{index}.json',request),
                            reply=save(destination/f'reply-{index}.json',reply),evidence_directory=str(evidence)))
        cases.append(dict(name=f'anchor-{index}',request=encoded(request),witness=encoded(raw_witness),
                          identity=identity,token=sent['commandID'],accept=True))
        if index < 3:
            permit = protocol.request(phase,2,'permit',t.sha(reply),inspected=t.sha(reply),display='c'*64)
            permit = t.load(permit)
            granted = t.encode(dict(challenge=phase,sequence=2,commandID=permit['commandID'],requestSHA256=t.sha(t.encode(permit)),
                operation='permit',outcome='granted',inspectedReplySHA256=t.sha(reply),displayReceiptSHA256='c'*64))
            grants.append(save(destination/f'grant-{index}.json',granted))
    def add(name, change):
        value = copy.deepcopy(cases[0]); value.update(name=name,accept=False); change(value); cases.append(value)
    def request_change(value, change):
        raw=t.load(capture.decode(value['request'])); change(raw); value['request']=encoded(t.encode(raw))
    def witness_change(value, change):
        raw=t.load(capture.decode(value['witness'])); change(raw); value['witness']=encoded(t.encode(raw))
    final = copy.deepcopy(cases[3]); final['name']='collection-wrong-final'
    request_change(final,lambda r:r['challenge'].update(finalInvocationSequence=r['challenge']['finalInvocationSequence']+1))
    cases.append(final)  # Payload construction cannot replace the independent semantic join.
    add('bad-token',lambda v:v.update(token='old-token'))
    add('replayed-token',lambda v:v.update(token=cases[1]['token']))
    add('foreign-process',lambda v:request_change(v,lambda r:r['challenge']['identity'].update(processID=999)))
    add('wrong-phase-name',lambda v:request_change(v,lambda r:r['challenge'].update(name='RUN')))
    add('permit-as-inspection',lambda v:request_change(v,lambda r:r.update(operation='permit')))
    add('boolean-sequence',lambda v:request_change(v,lambda r:r.update(sequence=True)))
    add('unexpected-request-field',lambda v:request_change(v,lambda r:r.update(extra='ignored')))
    add('foreign-native-run',lambda v:witness_change(v,lambda w:w.update(runID='foreign')))
    add('aliased-window',lambda v:witness_change(v,lambda w:w['snapshot']['continuity']['owners'][1].update(
        windowIdentity=w['snapshot']['continuity']['owners'][0]['windowIdentity'])))
    add('boolean-generation',lambda v:witness_change(v,lambda w:w['snapshot']['continuity']['owners'][0].update(generation=True)))
    add('missing-observer',lambda v:witness_change(v,lambda w:w['snapshot']['input'][1].update(observerIdentity='')))
    add('native-failure',lambda v:witness_change(v,lambda w:w['snapshot'].update(failure='lost')))
    save(destination/'cases.json',t.encode(cases)); save(destination/'control.swift',channel.source().encode())
    inputs = dict(identity=identity,anchors=anchors,phase_replies=grants,native_runs=0,gates_closed=[])
    save(destination/'inputs.json',t.encode(inputs))
    return dict(controls=len(cases),native_runs=0,gates_closed=[])


def verify(preparation, swift_output, decoder, output):
    preparation, swift_output, decoder, output = map(Path,[preparation,swift_output,decoder,output])
    t.require(not output.exists(), 'display verification output reused'); output.mkdir()
    inputs=t.load((preparation/'inputs.json').read_bytes()); anchors=copy.deepcopy(inputs['anchors'])
    source_sha=media.sha(HERE/'operation_display.swift'); binary_sha=media.sha(decoder)
    results=[]
    def image(name,payloads,scale=1):
        folder=output/name;folder.mkdir()
        save(folder/'fixture.json',t.encode(dict(payloads=payloads,scale=scale)))
        argv=[str(decoder),'fixture',str(folder/'fixture.json'),str(folder/'image.png')]
        save(folder/'invocation.json',t.encode(dict(argv=argv,decoder_sha256=binary_sha,native_runs=0)))
        proc=subprocess.run(argv,capture_output=True,timeout=60)
        save(folder/'process.json',t.encode(dict(returncode=proc.returncode,stdout=proc.stdout.decode(),stderr=proc.stderr.decode())))
        t.require(proc.returncode==0,'generated display image failed')
        return media.decode(decoder,binary_sha,'IMAGE',folder/'image.png',folder/'decode',60,source_sha256=source_sha)
    def payloads(index):
        d=t.load(read(anchors[index]['descriptor']))
        return [p for pair in d['payloads'].values() for p in pair.values()]
    def read(ref): return media.verified_ref(ref,capture.MAXIMUM_BYTES)
    for i,anchor in enumerate(anchors):
        anchor['descriptor']=media.reference(swift_output/f'anchor-{i}.json')
        anchor['image']=image(f'image-{i}',payloads(i),[1,2,3,1][i])
    def check(name, candidate=None, grants=None, accept=False):
        candidate = copy.deepcopy(anchors) if candidate is None else candidate
        try:
            result=display.assess(candidate,grants or inputs['phase_replies'],inputs['identity'],
                                   decoder_source_sha256=source_sha,decoder_binary_sha256=binary_sha)
            save(output/(name+'-result.json'),t.encode(result))
            t.require(result['native_acceptance'] is False and not result['gates_closed'],'component claimed native credit')
            results.append(dict(name=name,accepted=True,pass_=accept))
        except Exception as error:
            results.append(dict(name=name,accepted=False,pass_=not accept,error_type=type(error).__name__,reason=str(error)))
    def altered(index,key,change,name):
        a=copy.deepcopy(anchors); value=t.load(read(a[index][key])); change(value)
        a[index][key]=save(output/(name+'.json'),t.encode(value)); return a
    def changed_capture(index,change,name):
        a=copy.deepcopy(anchors);reply=t.load(read(a[index]['reply']))
        ref=t.load(capture.decode(reply['observation']))
        cap=t.load(capture.read_reference(a[index]['evidence_directory'],ref),maximum=capture.MAXIMUM_BYTES)
        change(cap);raw=t.encode(cap);digest=t.sha(raw);new=dict(name='capture-'+digest+'.json',sha256=digest,bytes=len(raw))
        evidence=output/(name+'-evidence');evidence.mkdir();save(evidence/new['name'],raw)
        observation=t.encode(new);reply.update(observation=encoded(observation),observationSHA256=t.sha(observation))
        a[index]['reply']=save(output/(name+'-reply.json'),t.encode(reply));a[index]['evidence_directory']=str(evidence)
        return a
    check('complete-four-anchors',accept=True)
    a=copy.deepcopy(anchors);a[1]['image']=image('background-with-old-a',payloads(1)+payloads(0)[:2],2)
    check('old-a-retained-without-foreground-credit',a,accept=True)
    a=copy.deepcopy(anchors);a[1]['image']=image('unrelated-qr',payloads(1)+['unrelated-content'],1)
    check('unrelated-qr-is-not-an-owner',a,accept=True)
    a=copy.deepcopy(anchors);a[2]['image']=image('stale-a',payloads(2)[2:]+payloads(0)[:2],2)
    check('old-a-cannot-prove-foreground',a)
    a=copy.deepcopy(anchors);a[1]['image']=image('missing-b',payloads(1)[:1]);check('missing-phase-marker',a)
    a=copy.deepcopy(anchors);a[1]['image']=image('duplicate-b',payloads(1)+payloads(1)[:1]);check('duplicate-marker',a)
    a=copy.deepcopy(anchors);a[0]['image']=image('foreign-marker',payloads(0)[:3]+['DDH10|foreign']);check('foreign-marker',a)
    a=copy.deepcopy(anchors);a[1]['image']=anchors[0]['image'];check('reused-image',a)
    check('missing-anchor',anchors[:3])
    a=copy.deepcopy(anchors);a[1],a[2]=a[2],a[1];check('out-of-order-anchor',a)
    for name,key,change in [
        ('foreign-token','descriptor',lambda d:d.update(token='not-a-token')),
        ('replayed-token','descriptor',lambda d:d.update(token=t.load(read(anchors[0]['descriptor']))['token'])),
        ('wrong-context','descriptor',lambda d:d.update(contextSHA256='0'*64)),
        ('wrong-owner','descriptor',lambda d:d['owners'][1].update(windowIdentity='other')),
        ('wrong-payload','descriptor',lambda d:d['payloads']['scene-B'].update(owner='DDH10|other')),
        ('wrong-request-binding','reply',lambda d:d.update(requestSHA256='0'*64)),
        ('wrong-native-binding','descriptor',lambda d:d.update(witness=encoded(t.encode({'runID':'other'})))),
        ('foreign-phase-request','request',lambda d:d['challenge'].update(challengeID=str(uuid.uuid4()))),
        ('missing-raw-descriptor','descriptor',lambda d:d.pop('witness'))]:
        check(name,altered(1,key,change,name))
    grants=copy.deepcopy(inputs['phase_replies']); grants[1]=grants[0];check('reused-consumed-reply',grants=grants)
    a=copy.deepcopy(anchors);a[3]['descriptor']=media.reference(swift_output/'collection-wrong-final.json')
    wrong=t.load(read(a[3]['descriptor']));request_raw=capture.decode(wrong['request']);request=t.load(request_raw)
    reply=t.load(read(a[3]['reply']));reply.update(challenge=request['challenge'],requestSHA256=t.sha(request_raw))
    a[3]['request']=save(output/'wrong-final-request.json',request_raw)
    a[3]['reply']=save(output/'wrong-final-reply.json',t.encode(reply));check('wrong-final-invocation',a)
    check('truncated-recorder-prefix',changed_capture(1,lambda c:c['snapshot']['signals'].pop(),'truncated-prefix'))
    def semantic_owner(cap):
        rows=[t.load(capture.decode(raw)) for raw in cap['snapshot']['signals']]
        for row in rows:
            if 'reason' in row:
                witness=json.loads(row['reason']);witness['snapshot']['input'][1]['observerIdentity']='other-observer'
                row['reason']=json.dumps(witness)
        cap['snapshot']['signals']=[encoded(t.encode(row)) for row in rows]
    check('semantic-owner-differs-from-anchor',changed_capture(3,semantic_owner,'different-semantic-owner'))
    # Corrupt a copy, keeping every original descriptor/media/capture immutable.
    a=copy.deepcopy(anchors); bad=output/'invalid-manifest.json';bad.write_text('{}')
    a[3]['image']=media.reference(bad);check('unbound-decoder-manifest',a)
    summary=dict(state='PASS' if all(r['pass_'] for r in results) else 'FAIL',controls=len(results),results=results,
                 decoder_source_sha256=source_sha,decoder_binary_sha256=binary_sha,native_runs=0,gates_closed=[])
    save(output/'inputs.json',t.encode(dict(anchors=anchors,phase_replies=inputs['phase_replies'],identity=inputs['identity'])))
    save(output/'result.json',t.encode(summary));return summary

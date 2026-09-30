"""Actual saved Swift protocol bytes and synthetic device IO; never native proof."""
import base64
import copy
import json
from pathlib import Path
from unittest.mock import patch

import operation_transport as t
import scene_background_capture as capture
import scene_background_cycle as cycle
import scene_background_host as host
import scene_background_protocol as protocol


def put(files, prefix, label, value):
    raw = t.encode(value); digest = t.sha(raw); name = label+'-'+digest+'.json'
    files[prefix+name] = raw
    return dict(name=name, sha256=digest, bytes=len(raw))


def encoded(raw): return base64.b64encode(raw).decode()


class Device:
    """Return native-shaped receipts around copied synthetic Swift captures."""
    def __init__(self, root, saved, mode):
        self.saved = saved; self.mode = mode; self.identifier = 'offline-h10-device'
        self.output = root/'device-io'; self.output.mkdir(); self.sequence = 0; self.calls = []
        self.identity = t.load((saved/'challenge.json').read_bytes())
        self.prefix = 'Documents/'+self.identity['runID']+'.background-channel/'
        self.files = {self.prefix+str(p.relative_to(saved)):p.read_bytes() for p in saved.rglob('*') if p.is_file()}
        self.consumed = []; self.missed = False

    def returned(self, args, label, deadline, missing):
        self.sequence += 1
        folder = self.output/f'{self.sequence:05d}-{label}'; folder.mkdir()
        result = dict(info=dict(commandType='devicectl.'+'.'.join(args[:3]),
            outcome='failed' if missing else 'success', arguments=['devicectl',*args[:3],
                '--device',self.identifier,*args[3:]]), result={})
        if missing:
            result.update(errorSignature='(com.apple.dt.CoreDeviceError 7000)',
                error=dict(domain='com.apple.dt.CoreDeviceError',code=7000,
                    userInfo=dict(NSLocalizedDescription=dict(string='Failed to retrieve the file node for '+missing))))
            if self.mode == 'malformed-missing': result['error']['code'] = 999
        if self.mode == 'wrong-transfer-device': result['info']['arguments'][5] = 'foreign-device'
        raw = t.encode(result); (folder/'response.json').write_bytes(raw)
        receipt = dict(started_at=1.0, finished_at=1.0, deadline=deadline, returncode=1 if missing else 0,
                       before=[], remaining=[], quiescence_error=None, response_sha256=t.sha(raw))
        if self.mode == 'late-transfer': receipt['finished_at'] = deadline
        if self.mode == 'unreaped-transfer': receipt['remaining'] = [999]
        (folder/'receipt.json').write_bytes(t.encode(receipt))
        if self.mode == 'substituted-return': result = result|dict(substituted=True)
        return result, receipt

    def push(self, bundle, source, destination, label, deadline):
        self.calls.append(('push', destination)); raw = Path(source).read_bytes(); self.files[destination] = raw
        if destination.endswith('command.request'):
            folder = destination.rsplit('/',1)[0]+'/'
            sent = self.files[folder+raw.decode()+'.json']; request = t.load(sent)
            phase = request['challenge']; operation = request['operation']
            result = {key:request[key] for key in ['challenge','sequence','commandID','operation']}
            result.update(requestSHA256=t.sha(sent), outcome={'inspect':'observed','permit':'granted','seal':'sealed'}[operation])
            original_folder = self.saved/('collection' if phase['phase']==3 else f'phase-{phase["phase"]}')
            original = next(t.load(p.read_bytes()) for p in original_folder.glob('*.reply.json')
                            if t.load(p.read_bytes())['operation'] == operation)
            if operation == 'inspect':
                result.update(observation=original['observation'], observationSHA256=original['observationSHA256'])
                if self.mode == 'wrong-observation-hash': result['observationSHA256'] = 'e'*64
            else:
                result.update({key:request[key] for key in ['inspectedReplySHA256','displayReceiptSHA256']})
                if operation == 'seal':
                    seal_ref=t.load(capture.decode(original['seal']))
                    seal=t.load(self.files[self.prefix+'evidence/'+seal_ref['name']], maximum=capture.MAXIMUM_BYTES)
                    seal.update(challenge=phase, semanticProof=request['semanticProof'],
                                displayReceiptSHA256=request['displayReceiptSHA256'])
                    if self.mode == 'wrong-seal-proof': seal['displayReceiptSHA256'] = 'e'*64
                    reference=put(self.files,self.prefix+'evidence/','seal',seal)
                    result['seal']=encoded(t.encode(reference))
            if self.mode == 'wrong-reply-request': result['requestSHA256'] = 'e'*64
            returned = t.encode(result); self.files[folder+t.sha(sent)+'.reply.json'] = returned
            if operation == 'permit':
                self.consumed.append(t.sha(returned))
                value=dict(permitRequestSHA256=t.sha(sent),permitReplySHA256=t.sha(returned))
                if self.mode == 'wrong-consumed': value['permitReplySHA256']='e'*64
                self.files[folder+'consumed.json']=t.encode(value)
        args=['device','copy','to','--domain-type','appDataContainer','--domain-identifier',bundle,
              '--source',str(source),'--destination',destination]
        return self.returned(args,label,deadline,None)

    def pull(self, bundle, source, destination, label, deadline, *, check):
        self.calls.append(('pull', source))
        missing = source not in self.files
        if self.mode in ['missing-once','malformed-missing'] and not self.missed:
            missing=True; self.missed=True
        if self.mode == 'missing-reply-once' and source.endswith('.reply.json') and not self.missed:
            missing=True; self.missed=True
        if not missing:
            raw=self.files[source]
            if source.endswith('collection/challenge.json'):
                value=t.load(raw); value['consumedPhaseReplies']=list(self.consumed)
                if self.mode == 'wrong-collection-phase': value['consumedPhaseReplies'][0]='e'*64
                if self.mode == 'wrong-final-invocation': value['finalInvocationSequence']+=1
                raw=t.encode(value)
            if source.endswith('challenge.json'):
                if self.mode == 'foreign-process':
                    value=t.load(raw);value['identity']['processID']+=1;raw=t.encode(value)
                if self.mode == 'duplicate-field': raw=raw[:-1]+b',"phase":0}'
            if '/evidence/' in source and self.mode == 'corrupt-artifact': raw=b'changed'
            Path(destination).write_bytes(raw)
        args=['device','copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,
              '--source',source,'--destination',str(destination)]
        return self.returned(args,label,deadline,source if missing else None)


class Boundary:
    """Synthetic proof callback; its bytes do not establish physical visibility."""
    def __init__(self, mode): self.mode=mode

    def validate(self, context, actual, folder):
        result=dict(context,state='PASS_SOURCE_BOUND_H10_BOUNDARY')
        for kind,raw in [('display',b'SYNTHETIC_DISPLAY_ONLY'),('native',t.encode(actual['after']))]:
            path=folder/(kind+'.raw');path.write_bytes(raw)
            result[kind]=dict(name=path.name,sha256=t.sha(raw),bytes=len(raw))
        if self.mode == 'stale-boundary': result['inspectionReplySHA256']='e'*64
        if self.mode == 'digest-only-boundary': (folder/result['display']['name']).unlink()
        if self.mode == 'symlink-boundary':
            p=folder/result['display']['name'];p.rename(folder/'original');p.symlink_to(folder/'original')
        if self.mode == 'rejected-boundary': result['state']='UNQUALIFIED'
        return t.encode(result)


def verify(saved, destination):
    saved=Path(saved); destination=Path(destination)
    t.require(destination.is_absolute() and not destination.exists(), 'fresh H10 host controls required')
    destination.mkdir(); results=[]
    identity=t.load((saved/'challenge.json').read_bytes()); consumed=[]
    # These are actual saved Swift request/reply bytes, not synthesized expected encodings.
    for index,name in enumerate(['phase-0','phase-1','phase-2','collection']):
        folder=saved/name; raw=(folder/'challenge.json').read_bytes()
        value=protocol.challenge(raw,identity,index,consumed); previous=t.sha(raw); inspected=None
        replies=sorted([(t.load(p.read_bytes())['sequence'],p) for p in folder.glob('*.reply.json')])
        for sequence,path in replies:
            returned=path.read_bytes(); message=t.load(returned); sent=(folder/(message['requestSHA256']+'.json')).read_bytes()
            request=t.load(sent);operation=request['operation']
            rebuilt=protocol.request(value,sequence,operation,previous,inspected=inspected if operation!='inspect' else None,
                display=request.get('displayReceiptSHA256'), command_id=request['commandID'],
                proof=capture.decode(request['semanticProof']) if 'semanticProof' in request else None)
            t.require(rebuilt==sent,'Python request does not match actual Swift bytes')
            protocol.reply(returned,sent,received_ms=1000);previous=t.sha(returned)
            if operation=='inspect':inspected=previous
            if operation=='permit':
                protocol.consumed((folder/'consumed.json').read_bytes(),sent,returned);consumed.append(previous)
        results.append(dict(name='actual-swift-bytes-'+name,passed=True))
    modes=['complete','missing-once','missing-reply-once','reused-inspection','foreign-process','duplicate-field','late-transfer','unreaped-transfer',
        'substituted-return','wrong-transfer-device','malformed-missing','wrong-reply-request',
        'wrong-observation-hash','corrupt-artifact','wrong-consumed','wrong-collection-phase','wrong-final-invocation',
        'wrong-seal-proof','no-boundary-validator','stale-boundary','digest-only-boundary','symlink-boundary',
        'rejected-boundary','mutated-capture','mutated-definition','changed-cutoff','changed-device','duplicate-permit',
        'mutated-io-response','mutated-io-receipt','mutated-transfer-manifest']
    for mode in modes:
        folder=destination/mode;folder.mkdir();failure=None;channel=None
        with patch('time.time',return_value=1.0):
            device=Device(folder,saved,mode)
            validator=None if mode=='no-boundary-validator' else Boundary(mode).validate
            channel=host.Channel(device,'com.datadoghq.offline.h10',folder/'host',device.identity,
                                 boundary_validator=validator,wait=lambda:None)
            try:
                channel.begin();channel.inspect()
                if mode=='reused-inspection':channel.inspect()
                if mode=='mutated-capture':(channel.evidence/channel.latest['name']).write_bytes(b'changed')
                if mode=='mutated-definition':(channel.output/'definition.json').write_bytes(b'changed')
                if mode=='changed-cutoff':channel.deadline+=100
                if mode=='changed-device':device.identifier='other-device'
                if mode in ['mutated-io-response','mutated-io-receipt']:
                    kind=mode.removeprefix('mutated-io-')
                    next((channel.output/'io').glob('*-'+kind+'.json')).write_bytes(b'changed')
                channel.permit()
                if mode=='duplicate-permit':channel.permit()
                if mode=='mutated-transfer-manifest':(channel.folder/'transfer-manifest.json').write_bytes(b'changed')
                for _ in range(2):channel.begin();channel.inspect();channel.permit()
                channel.begin();channel.inspect();value=channel.seal()
                t.require(value['state']=='PASS_SEALED_LOCAL_COMPONENT_ONLY' and channel.sealed,'host did not seal')
                manifest=t.load((channel.folder/'transfer-manifest.json').read_bytes(),maximum=capture.MAXIMUM_BYTES)
                t.require(all(t.sha((channel.output/path).read_bytes())==sha for path,sha in manifest['records'].items()),
                          'host final manifest does not preserve actual bytes')
                t.require({str(p.relative_to(channel.output)) for p in (channel.output/'io').iterdir()}
                          <= set(manifest['records']), 'host final manifest omits raw transfer evidence')
            except Exception as error:failure=type(error).__name__+': '+str(error)
            positive=mode in ['complete','missing-once','missing-reply-once']
            passed=(failure is None)==positive
            if failure is not None:
                calls=len(device.calls)
                try:channel.inspect();passed=False
                except Exception:pass
                passed=passed and channel.failed and len(device.calls)==calls and (channel.output/'failure.json').is_file()
            results.append(dict(name=mode,passed=passed,failure=failure))
    value=dict(state='PASS' if all(r['passed'] for r in results) else 'FAIL',checks=results,
        source={str(Path(module.__file__)):t.sha(Path(module.__file__).read_bytes()) for module in [host,protocol,capture,cycle]},
        saved_swift_source=str(saved),native_runs=0,gates_closed=[],
        scope='Actual saved Swift byte compatibility; real ObservedDevice receipt checks with a synthetic remote, clock and display validator. No physical visibility or native process is qualified.')
    (destination/'result.json').write_text(json.dumps(value,indent=2)+'\n')
    return value

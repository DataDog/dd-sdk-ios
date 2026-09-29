"""Synthetic receipt controls. No device commands, generated pixels or native credit."""
import base64
import copy
import json
from pathlib import Path
import time
import unittest
import uuid
from unittest.mock import patch

import operation_display as pixels
import operation_display_proof as p
import operation_transport as t
import test_operation_display as pixel_controls
import test_operation_setup as host_controls


class BridgeTests(unittest.TestCase):
    def harness(self):
        host = host_controls.HostSetupTests(methodName='runTest')
        original = host_controls.transport_controls.OperationSetupTransportTests.fixture
        def fixture(_):
            identity, args = original(_)
            identity['runID'] = str(uuid.uuid4()); args['run_id'] = identity['runID']
            return identity, args
        with patch.object(host_controls.transport_controls.OperationSetupTransportTests, 'fixture', fixture):
            host.setUp()
        self.addCleanup(host.doCleanups)
        host.collect()
        # Display messages are opaque; do not feed them to the input-capture double.
        def push(bundle, source, destination, label, deadline):
            host.remote.files[destination] = Path(source).read_bytes()
            host.remote.calls.append(('push', destination))
            result, receipt = host.remote.result('to', bundle, source, destination)
            if host.remote.mutation == 'push-failure': receipt['returncode'] = 1
            return result, receipt
        host.remote.push = push
        source = host.root / 'codec.swift'; source.write_text('synthetic codec source')
        binary = host.root / 'codec'; binary.write_bytes(b'synthetic executable')
        host.bridge = p.DisplayProofBridge(host.setup, nonce=str(uuid.uuid4()),
            source_sha256=pixels.sha(source), binary_sha256=pixels.sha(binary))
        host.source = source; host.binary = binary
        host.binding_bytes = {scene:t.encode(binding) for scene,binding in host.bridge.bindings.items()}
        host.binding = pixels.identity(host.identity['runID'], host.bridge.nonce,
            {scene:t.sha(raw) for scene,raw in host.binding_bytes.items()})
        return host

    def receipt(self, h, expected_phase, **changes):
        phase = expected_phase
        index = p.PHASES.index(phase)
        geometry = dict(x=0.10000000000001, y=12.5, width=176.0, height=176.0)
        value = dict(schemaVersion=1, identity=h.identity, nonce=h.bridge.nonce, phase=phase,
            sequence=index, deadlineBits=h.bridge.bits, bindings=h.bridge.bindings,
            bindingSHA256=h.binding['owners'], surfaces={s:{'ownerInWindowPoints':geometry} for s in p.SCENES},
            geometryScope=p.GEOMETRY_SCOPE, nativeAcceptance=False)
        if index:
            value.update(previousReceiptSHA256=t.sha(h.bridge.receipts[p.PHASES[index-1]]),
                causeSHA256=t.sha(h.bridge.proofs['START']) if index==1 else t.sha(self.seal(h)))
        value.update(changes)
        return t.encode(value)

    def media(self, h, phase, *, movie=False, phases=None, binding=None):
        folder = h.root.resolve() / str(uuid.uuid4()); folder.mkdir(); (folder/'decoded').mkdir()
        raw = folder/('raw.mov' if movie else 'raw.png')
        source = h.setup.folder/'screen.png' if phase=='START' and not movie else h.root/(str(uuid.uuid4())+'.png')
        if source.name != 'screen.png': source.write_bytes(b'synthetic media '+phase.encode())
        raw.write_bytes(source.read_bytes())
        phases = phases or (p.PHASES if movie else [phase])
        rows = [pixel_controls.frame(binding or h.binding,(ph,ph),i) for i,ph in enumerate(phases)]
        for row in rows:
            row['width']=row['height']=200
            if not movie:row.pop('pts')
        (folder/'decoded/frames.jsonl').write_bytes(b''.join(t.encode(r)+b'\n' for r in rows))
        kind='MOVIE' if movie else 'IMAGE'
        decoder = dict(schemaVersion=1, state='DECODED', kind=kind, readerState='completed',
            nativeAcceptance=False, inputSHA256=pixels.sha(raw), framesSHA256=pixels.sha(folder/'decoded/frames.jsonl'),
            frameCount=len(rows), revision=3)
        if movie:decoder.update(trackCount=1,decodedOutput=True,pixelFormat=1111970369)
        pixels.save(folder/'decoded/decoder.json',decoder)
        invocation=dict(argv=[str(h.binary.resolve()),kind.lower(),str(raw),str(folder/'decoded')],
            binary=pixels.reference(h.binary),decoder_source=pixels.reference(h.source),raw=pixels.reference(raw),
            source=pixels.reference(source),resource_timeout=60,started_at=time.time(),native_acceptance=False)
        pixels.save(folder/'invocation.json',invocation)
        pixels.save(folder/'process.json',dict(returncode=0,timed_out=False,finished_at=time.time()))
        value=dict(schema_version=1,kind=kind,decoder_source=pixels.reference(h.source),
            executable=pixels.reference(h.binary),invocation=pixels.reference(folder/'invocation.json'),
            process=pixels.reference(folder/'process.json'),raw=pixels.reference(raw),
            decoder=pixels.reference(folder/'decoded/decoder.json'),frames=pixels.reference(folder/'decoded/frames.jsonl'),
            native_acceptance=False)
        pixels.save(folder/'manifest.json',value)
        return pixels.reference(folder/'manifest.json')

    def start(self,h):
        return h.bridge.start(self.receipt(h,'START'),h.binding_bytes,self.media(h,'START'))

    def prepare(self,h):
        self.start(h)
        return h.bridge.run(self.receipt(h,'RUN'),self.media(h,'RUN'))

    def seal(self,h):
        return t.encode(dict(index=21,boundary='collection-seal',sample=dict(before=h.remote.snapshot,after=h.remote.snapshot)))

    def final(self,h,**kwargs):
        return h.bridge.final(kwargs.get('receipt',self.receipt(h,'FINAL')),kwargs.get('seal',self.seal(h)),
            kwargs.get('screenshot',self.media(h,'FINAL')),kwargs.get('movie',self.media(h,'FINAL',movie=True)))

    def invalid(self,h,call):
        with self.assertRaises((ValueError,KeyError,TypeError,FileExistsError)):call()
        self.assertTrue(h.bridge.failed);self.assertTrue(h.channel.stopped)
        self.assertTrue((h.bridge.folder/'failure.json').exists())

    def test_complete_typed_chain_keeps_original_host_collection_and_no_acceptance(self):
        h=self.harness();original={path:path.read_bytes() for path in h.setup.folder.iterdir()}
        run=self.prepare(h);published=h.setup.publish()
        self.assertEqual(h.bridge.state,'HOST_PUBLISHED')
        for path,raw in original.items():self.assertEqual(path.read_bytes(),raw)
        envelope=t.load((h.setup.folder/'publication'/('host-publication-'+published+'.json')).read_bytes(),maximum=t.MAX_CONTEXT_BYTES)
        proof=t.load(base64.b64decode(envelope['proof']),maximum=t.MAX_CONTEXT_BYTES)
        self.assertEqual(base64.b64decode(proof['displayProof']),run)
        self.assertEqual(proof['artifacts']['result.json'],t.sha(original[h.setup.folder/'result.json']))
        self.final(h);self.assertEqual(h.bridge.state,'FINAL_PUBLISHED')
        result=t.load((h.bridge.folder/'result.json').read_bytes());self.assertFalse(result['nativeAcceptance'])
        self.assertEqual(result['gatesClosed'],[])
        for phase in p.PHASES:
            value=t.load(h.bridge.proofs[phase],maximum=t.MAX_CONTEXT_BYTES)
            self.assertEqual(t.encode(value),h.bridge.proofs[phase])
            self.assertEqual(value['deadlineBits'],h.bridge.bits)
            self.assertEqual(set(value['anchors']),set(p.PHASES[:p.PHASES.index(phase)+1]))
            self.assertEqual('movie' in value,phase=='FINAL')
            for typed in value['anchors'].values():
                self.assertEqual(set(typed),{'reference','manifest','decoder','invocation','process'})
                for name in ['manifest','decoder','invocation','process']:
                    self.assertEqual(t.sha(base64.b64decode(typed[name]['bytes'])),typed[name]['sha256'])

    def test_existing_completion_consumes_the_selected_extension_after_final(self):
        import operation_completion
        h = self.harness()
        run = self.prepare(h)
        h.setup.publish()
        self.final(h)
        local = operation_completion.Completion(h.setup)
        proof = operation_completion.decode_handoff(local.publication, h.identity, h.channel.deadline)
        self.assertEqual(base64.b64decode(proof['displayProof']), run)
        self.assertFalse((local.folder / 'result.json').exists())
        self.assertFalse(proof['sdkAdmitted'])

    def test_native_receipt_bytes_and_fractional_geometry_are_not_reserialized(self):
        h=self.harness();raw=json.dumps(t.load(self.receipt(h,'START')),indent=2).encode()
        h.bridge.start(raw,h.binding_bytes,self.media(h,'START'))
        self.assertEqual((h.bridge.folder/'native-START.json').read_bytes(),raw)
        self.assertEqual(t.load(h.bridge.proofs['START'])['nativeReceiptSHA256'],t.sha(raw))

    def test_missing_or_changed_native_binding_fails_before_request(self):
        for change in ['missing','foreign','alias']:
            h=self.harness();bindings=copy.deepcopy(h.binding_bytes)
            if change=='missing':bindings.pop('scene-B')
            elif change=='foreign':bindings['scene-A']=t.encode(dict(h.bridge.bindings['scene-A'],windowIdentity='other'))
            else:bindings['scene-B']=bindings['scene-A']
            count=len(h.remote.calls)
            self.invalid(h,lambda:h.bridge.start(self.receipt(h,'START'),bindings,self.media(h,'START')))
            self.assertEqual(len(h.remote.calls),count)

    def test_foreign_native_phase_identity_deadline_and_sequence_fail(self):
        for field,value in [('schemaVersion',True),('identity',{}),('nonce',str(uuid.uuid4())),
                            ('phase','RUN'),('sequence',True),('deadlineBits','0'),('nativeAcceptance',True)]:
            h=self.harness()
            self.invalid(h,lambda:h.bridge.start(self.receipt(h,'START',**{field:value}),h.binding_bytes,self.media(h,'START')))

    def test_start_image_must_be_the_original_collected_screenshot(self):
        h=self.harness();ref=self.media(h,'START');folder=Path(ref['path']).parent
        invocation=t.load((folder/'invocation.json').read_bytes());other=h.root/'other.png';other.write_bytes((h.setup.folder/'screen.png').read_bytes())
        invocation['source']=pixels.reference(other);(folder/'invocation.json').write_bytes(t.encode(invocation))
        manifest=t.load(Path(ref['path']).read_bytes());manifest['invocation']=pixels.reference(folder/'invocation.json')
        Path(ref['path']).write_bytes(t.encode(manifest));ref=pixels.reference(ref['path'])
        self.invalid(h,lambda:h.bridge.start(self.receipt(h,'START'),h.binding_bytes,ref))

    def test_foreign_markers_wrong_phase_and_codec_reject(self):
        for problem in ['foreign','phase','codec']:
            h=self.harness();ref=self.media(h,'RUN' if problem=='phase' else 'START',
                binding=pixel_controls.binding() if problem=='foreign' else None)
            if problem=='codec':h.binary.write_bytes(b'changed')
            self.invalid(h,lambda:h.bridge.start(self.receipt(h,'START'),h.binding_bytes,ref))

    def test_changed_native_or_media_evidence_consumes_the_attempt(self):
        for name in ['native-START.json','source','binary','process','frames']:
            h=self.harness();self.start(h)
            if name=='native-START.json':path=h.bridge.folder/name
            elif name in ['source','binary']:path=getattr(h,name)
            else:
                manifest=t.load(Path(h.bridge.anchors['START']['path']).read_bytes());path=Path(manifest[name]['path'])
            path.write_bytes(path.read_bytes()+b' ')
            self.invalid(h,lambda:h.bridge.run(self.receipt(h,'RUN'),self.media(h,'RUN')))

    def test_phase_reuse_order_and_expiry_cannot_recover(self):
        for problem in ['early-run','reused-start','expired']:
            h=self.harness()
            if problem!='early-run':self.start(h)
            if problem=='early-run':self.invalid(h,lambda:h.bridge.run(b'{}',self.media(h,'RUN')))
            elif problem=='reused-start':self.invalid(h,lambda:self.start(h))
            else:
                with patch.object(t.time,'time',return_value=h.channel.deadline):
                    self.invalid(h,lambda:h.bridge.run(self.receipt(h,'RUN'),self.media(h,'RUN')))
            with self.assertRaises(ValueError):h.bridge.live()

    def test_partial_request_publication_stops_host_publication(self):
        h=self.harness();h.remote.mutation='push-failure'
        self.invalid(h,lambda:self.start(h));count=len(h.remote.calls)
        with self.assertRaises(ValueError):h.setup.publish()
        self.assertEqual(len(h.remote.calls),count)
        self.assertTrue((h.bridge.folder/'proof-START.json').exists())

    def test_host_cannot_publish_before_run_or_after_changed_parent(self):
        for problem in ['before-run','parent']:
            h=self.harness()
            if problem=='parent':
                self.prepare(h);(h.setup.folder/'result.json').write_bytes(b'{}')
            count=len(h.remote.calls);self.invalid(h,h.setup.publish)
            self.assertEqual(len(h.remote.calls),count)

    def test_native_run_requires_the_original_start_receipt_and_proof(self):
        for field in ['previousReceiptSHA256','causeSHA256']:
            h=self.harness();self.start(h)
            self.invalid(h,lambda:h.bridge.run(self.receipt(h,'RUN',**{field:'0'*64}),self.media(h,'RUN')))

    def test_changed_extension_after_publication_is_not_reused_for_final(self):
        h=self.harness();self.prepare(h);h.setup.publish()
        path=h.setup.folder/'display-extension.json';path.write_bytes(path.read_bytes()+b' ')
        self.invalid(h,lambda:self.final(h))

    def test_final_requires_host_publication_and_the_native_collection_seal(self):
        for problem in ['no-publication','wrong-boundary','foreign-owner','wrong-cause']:
            h=self.harness();self.prepare(h)
            if problem!='no-publication':h.setup.publish()
            kwargs={}
            if problem in ['wrong-boundary','foreign-owner']:
                seal=t.load(self.seal(h))
                if problem=='wrong-boundary':seal['boundary']='collection'
                else:seal['sample']['before']['input'][0]['windowIdentity']='foreign'
                kwargs['seal']=t.encode(seal)
            if problem=='wrong-cause':kwargs['receipt']=self.receipt(h,'FINAL',causeSHA256='f'*64)
            self.invalid(h,lambda:self.final(h,**kwargs))

    def test_failed_movie_and_missing_phase_do_not_publish_final(self):
        for problem in ['process','missing-phase']:
            h=self.harness();self.prepare(h);h.setup.publish()
            movie=self.media(h,'FINAL',movie=True,phases=['START','FINAL'] if problem=='missing-phase' else None)
            if problem=='process':
                manifest=t.load(Path(movie['path']).read_bytes());Path(manifest['process']['path']).write_text('{}')
            count=len(h.remote.calls);self.invalid(h,lambda:self.final(h,movie=movie))
            self.assertEqual(len(h.remote.calls),count)


if __name__=='__main__':unittest.main()

"""Setup failures stop admission without app installation or human input."""
import copy
import contextlib
import io
import json
from pathlib import Path
import struct
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import zlib

import physical_setup as setup
import physical_runtime as runtime
from acceptance_common import Rejected
from capture_io import encoded


def png(width, height, bits=8):
    def chunk(tag, data):
        return struct.pack('>I', len(data))+tag+data+struct.pack('>I', zlib.crc32(tag+data))
    return (b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, bits, 2, 0, 0, 0))
            +chunk(b'IDAT', zlib.compress((b'\0'+b'\0'*width*3*(bits//8))*height))+chunk(b'IEND', b''))


def display(device='ipad', *, portrait=False):
    return dict(info=dict(outcome='success', commandType='devicectl.device.info.displays', arguments=['--device', device]),
                result=dict(displays=[dict(displayId=1, primary=True, type={'integrated': {}}, backlightState='activeOn',
                    nativeSize=[12, 8], pointScale=2, bounds=[[0, 0], [12, 8]], nativeOrientation='rot270',
                    currentOrientation='rot270' if portrait else 'rot0')], orientation=dict(
                    currentDeviceNonFlatOrientation='portraitUpsideDown' if portrait else 'landscapeLeft',
                    currentDeviceOrientation='faceUp', currentDeviceOrientationLocked=False)))


class Readiness(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve(); self.capture = self.root/'setup'; self.capture.mkdir()
        (self.capture/'commands').mkdir(); self.device = 'ipad'; self.now = time.time(); self.start = self.now-20
        self.expected = dict(kind=setup.KIND, device=self.device, expected=setup.pose(display(), self.device), pixels=[12, 8])
        self.plan = dict(device=self.device, physical_setup=self.expected, plan_sha256='plan')
        self.image = self.capture/'setup.png'; self.image.write_bytes(png(12, 8))
        observations = {}
        for index, name in enumerate(['before', 'image', 'after']):
            folder = self.capture/'commands'/name; folder.mkdir(); path = folder/'response.json'
            raw = display(); raw['info']['arguments'] += ['--json-output', str(path)]
            if name == 'image':
                raw['info'].update(commandType='devicectl.device.capture.screenshot')
                raw['info']['arguments'] += ['--destination', str(self.image)]
                raw['result'] = dict(destination=self.image.as_uri(), deviceIdentifier=self.device, imageFormat='png', width=12, height=8)
            path.write_bytes(encoded(raw)); receipt = folder/'receipt.json'
            receipt.write_bytes(encoded(dict(returncode=0, before=[], remaining=[], quiescence_error=None,
                started_at=self.start+index*3, finished_at=self.start+index*3+2, deadline=self.start+index*3+3,
                response_sha256=setup.shared.sha(path))))
            returned = folder/'returned.json'; returned.write_bytes(encoded(dict(response=raw,receipt=json.loads(receipt.read_bytes()))))
            observations[name] = dict(response=setup.reference(path), receipt=setup.reference(receipt),returned=setup.reference(returned))
        self.proof = dict(kind=setup.KIND, state='PASS', plan_sha256='plan', device=self.device, expected=self.expected,
            started_at=self.start, finished_at=self.start+9, deadline=self.now+90, image=setup.reference(self.image), observations=observations)
        self.bind_admission()
        self.save()

    def bind_admission(self):
        path=self.capture/'admission.json';path.write_bytes(encoded({k:self.proof[k] for k in ['kind','plan_sha256','device','expected','started_at','deadline']}))
        self.proof['admission']=setup.reference(path)

    def save(self):
        (self.capture/'setup.json').write_bytes(encoded(self.proof))

    def edit_response(self, name, mutate):
        entry = self.proof['observations'][name]; path = Path(entry['response']['path']); raw = json.loads(path.read_bytes()); mutate(raw)
        path.write_bytes(encoded(raw)); entry['response'] = setup.reference(path)
        receipt_path = Path(entry['receipt']['path']); receipt = json.loads(receipt_path.read_bytes())
        receipt['response_sha256'] = entry['response']['sha256']; receipt_path.write_bytes(encoded(receipt))
        entry['receipt'] = setup.reference(receipt_path)
        returned=Path(entry['returned']['path']);returned.write_bytes(encoded(dict(response=raw,receipt=receipt)))
        entry['returned']=setup.reference(returned);self.save()

    def check(self): return setup.validate(self.capture, self.plan, self.now)

    def test_landscape_actual_display_image_and_receipts_qualify_setup_only(self):
        self.assertEqual(self.check(), self.proof)
        self.assertNotIn('release_acceptance', self.proof)

    def test_portrait_with_internally_consistent_portrait_image_is_not_the_saved_setup(self):
        for name in ['before', 'after']:
            self.edit_response(name, lambda r: r.update(result=display(portrait=True)['result']))
        self.image.write_bytes(png(8, 12)); self.proof['image'] = setup.reference(self.image)
        self.edit_response('image', lambda r: r['result'].update(width=8, height=12)); self.save()
        with self.assertRaises(Rejected): self.check()

    def test_rotation_between_display_observations_rejects(self):
        self.edit_response('after', lambda r: r.update(result=display(portrait=True)['result']))
        with self.assertRaises(Rejected): self.check()

    def test_screenshot_axes_must_match_actual_pixels(self):
        self.edit_response('image', lambda r: r['result'].update(width=8, height=12))
        with self.assertRaises(Rejected): self.check()

    def test_foreign_or_ambiguous_device_is_rejected(self):
        self.edit_response('before', lambda r: r['info']['arguments'].extend(['--device', 'other']))
        with self.assertRaises(Rejected): self.check()

    def test_foreign_screenshot_destination_is_rejected(self):
        self.edit_response('image', lambda r: r['result'].update(destination='file:///old.png'))
        with self.assertRaises(Rejected): self.check()

    def test_actual_response_publication_is_bound(self):
        self.edit_response('after', lambda r: r['info']['arguments'].__setitem__(-1, '/old/response.json'))
        with self.assertRaises(Rejected): self.check()

    def test_original_receipt_hash_is_required(self):
        Path(self.proof['observations']['before']['response']['path']).write_bytes(encoded(display(portrait=True)))
        with self.assertRaises(Rejected): self.check()

    def test_late_failed_or_nonquiescent_receipt_rejects(self):
        for mutation in [dict(finished_at=self.now+100), dict(returncode=1), dict(remaining=[42]), dict(before=[42]),
                         dict(quiescence_error='unavailable'), dict(started_at=self.start-1), dict(response_sha256='old')]:
            with self.subTest(mutation=mutation):
                entry = self.proof['observations']['image']; path = Path(entry['receipt']['path']); original = path.read_bytes()
                value = json.loads(original); value.update(mutation); path.write_bytes(encoded(value)); entry['receipt'] = setup.reference(path); self.save()
                with self.assertRaises(Rejected): self.check()
                path.write_bytes(original); entry['receipt'] = setup.reference(path); self.save()

    def test_stale_proof_or_different_plan_rejects(self):
        for plan, now in [(dict(self.plan, plan_sha256='other'), self.now), (self.plan, self.now+301)]:
            with self.subTest(now=now, plan=plan['plan_sha256']), self.assertRaises(Rejected): setup.validate(self.capture, plan, now)

    def test_nonfinite_scale_and_boolean_bounds_reject(self):
        for mutation in [dict(pointScale=float('nan')), dict(bounds=[[False, 0], [12, 8]])]:
            raw = display(); raw['result']['displays'][0].update(mutation)
            with self.subTest(mutation=mutation), self.assertRaises(Rejected): setup.pose(raw, self.device)

    def test_truncated_corrupt_and_fake_png_pixels_reject(self):
        for image in [png(12, 8)[:-1], png(12, 8)[:40], png(12, 8).replace(b'IDAT', b'JUNK')]:
            with self.subTest(size=len(image)), self.assertRaises(Rejected): setup.png_size(image)

    def test_actual_home_16_bit_rgb_capture_format_is_supported(self):
        self.assertEqual(setup.png_size(png(12, 8, bits=16)), [12, 8])

    def test_admission_rejoins_setup_and_home_before_creating_native_admission(self):
        runtime_plan = dict(self.plan, evidence_contract=runtime.local.contract.CONTRACT, pair_seconds=2400)
        runtime_plan.pop('plan_sha256'); (self.root/'plan.json').write_bytes(encoded(runtime_plan))
        (self.root/'review.json').write_bytes(encoded(dict(state='PASS')))
        digest = setup.shared.sha(self.root/'plan.json'); self.proof['plan_sha256'] = digest; self.bind_admission(); self.save()
        home = self.root/'home.json'; home.write_bytes(encoded(dict(device=self.device, screenshot=self.proof['image'], display=self.expected['expected']['display'])))
        preflight = dict(plan_sha256=digest, at=self.now, state='PASS', device=self.device, backend='LOCAL_ONLY_NO_BACKEND_QUERY',
            physical_setup=setup.reference(self.capture/'setup.json'), initial_home=setup.reference(home),
            xcode_workspace=setup.reference(home), device_receipt=setup.reference(home))
        operator = dict(plan_sha256=digest, at=self.now, kind='OPERATOR_READY', user_message_reference='fresh readiness')
        a = self.root/'preflight.json'; b = self.root/'operator.json'; a.write_bytes(encoded(preflight)); b.write_bytes(encoded(operator))
        with patch.object(runtime, 'reviewed', return_value=runtime_plan), contextlib.redirect_stdout(io.StringIO()):
            runtime.stage(SimpleNamespace(root=self.root, preflight=a, operator=b))
        self.assertTrue((self.root/'native-admission.json').exists())

    def test_missing_setup_stops_before_admission(self):
        plan = dict(evidence_contract=runtime.local.contract.CONTRACT, device=self.device)
        (self.root/'plan.json').write_bytes(encoded(plan)); digest = setup.shared.sha(self.root/'plan.json')
        preflight = dict(plan_sha256=digest, at=self.now, state='PASS', device=self.device, backend='LOCAL_ONLY_NO_BACKEND_QUERY')
        operator = dict(plan_sha256=digest, at=self.now, kind='OPERATOR_READY', user_message_reference='fresh readiness')
        a = self.root/'preflight.json'; b = self.root/'operator.json'; a.write_bytes(encoded(preflight)); b.write_bytes(encoded(operator))
        with patch.object(runtime, 'reviewed', return_value=plan), self.assertRaises(KeyError):
            runtime.stage(SimpleNamespace(root=self.root, preflight=a, operator=b))
        self.assertFalse((self.root/'native-admission.json').exists())

    def test_preinstall_orientation_failure_never_installs_launches_or_prompts(self):
        (self.root/'cells').mkdir()
        plan = dict(device=self.device,udid='udid',required_os='27.0',cleanup_seconds=30,
                    evidence_contract=runtime.local.contract.CONTRACT,physical_setup=self.expected)
        (self.root/'plan.json').write_bytes(encoded(plan))
        selected = dict(id='candidate',arm='B',framework='UIKit',tracking='automatic')
        source = dict(arms={'B-device':dict(source='candidate-source',fixture='fixture')})
        signed = dict(products={'B-device-UIKit':dict(bundle='test.task',path='/test/product')})
        remote = Mock(identifier=self.device); remote.command.return_value = (display(), {})
        args = SimpleNamespace(root=self.root,key='candidate',native_deadline=self.now+100,
                               execution_deadline=self.now+110,cleanup_deadline=self.now+120)
        with patch.object(runtime,'reviewed',return_value=plan), patch.object(runtime,'admit',return_value=(selected,dict(
            cleanup_deadline=self.now+120,execution_deadline=self.now+110))), patch.object(runtime.local,'products',return_value=(source,signed)), \
            patch.object(runtime.io,'Device',return_value=remote), patch.object(runtime.io,'hardware',return_value=dict(os='27.0')), \
            patch.object(runtime.physical_setup,'capture',side_effect=Rejected('SETUP_NOT_READY')), \
            patch.object(runtime,'cleanup',return_value=[]) as cleanup, \
            contextlib.redirect_stdout(io.StringIO()):
            runtime.cell(args)
        self.assertEqual(remote.command.call_count,1)
        self.assertEqual(remote.command.call_args.args[0],['device','info','displays'])
        self.assertFalse(cleanup.call_args.args[4])  # No ownership of an installed task app.
        self.assertIsNone(cleanup.call_args.args[5])  # No collector or human prompt.
        summary = json.loads((self.root/'cells/candidate/summary.json').read_bytes())
        self.assertEqual(summary['scenario'],'UNQUALIFIED'); self.assertEqual(summary['cleanup'],'PASS')

    def test_old_receipts_cannot_be_refreshed_by_outer_proof_timestamps(self):
        self.proof['finished_at']=self.now+400;self.proof['deadline']=self.now+490;self.save()
        with self.assertRaises(Rejected):setup.validate(self.capture,self.plan,self.now+400)

    def test_actual_return_witness_rejects_coherent_response_and_receipt_replacement(self):
        entry=self.proof['observations']['before'];response=Path(entry['response']['path']);receipt=Path(entry['receipt']['path'])
        raw=json.loads(response.read_bytes());raw['result']=display(portrait=True)['result'];response.write_bytes(encoded(raw))
        value=json.loads(receipt.read_bytes());value['response_sha256']=setup.shared.sha(response);receipt.write_bytes(encoded(value))
        entry.update(response=setup.reference(response),receipt=setup.reference(receipt));self.save()
        with self.assertRaises(Rejected):self.check()

    def test_capture_preserves_and_rejects_files_replaced_after_return(self):
        class Replaced:
            def __init__(other,identifier,output):
                other.output=output;output.mkdir();other.sequence=0
            def command(other,args,label,deadline,**kwargs):
                other.sequence+=1;folder=other.output/(str(other.sequence).zfill(5)+'-'+label);folder.mkdir()
                path=folder/'response.json';raw=display(portrait=True);raw['info']['arguments']+=['--json-output',str(path)]
                original=encoded(raw);receipt=dict(response_sha256=__import__('hashlib').sha256(original).hexdigest())
                replacement=copy.deepcopy(raw);replacement['result']=display()['result'];path.write_bytes(encoded(replacement))
                (folder/'receipt.json').write_bytes(encoded(dict(receipt,response_sha256=setup.shared.sha(path))))
                return raw,receipt
        out=self.root/'new-capture'
        with patch.object(setup.io,'Device',Replaced),self.assertRaises(Rejected):setup.capture(out,self.plan,time.time()+120)
        saved=json.loads((out/'commands/00001-before/returned.json').read_bytes())
        self.assertEqual(saved['response']['result']['orientation']['currentDeviceNonFlatOrientation'],'portraitUpsideDown')
        self.assertEqual(json.loads((out/'setup.json').read_bytes())['state'],'SETUP_NOT_READY')


if __name__ == '__main__': unittest.main()

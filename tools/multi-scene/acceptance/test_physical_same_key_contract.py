"""H01 failure discriminators; the synthetic fixture is never physical evidence."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from acceptance_common import Rejected
import physical_same_key_contract as p

RUN = 'exp196-unit-same-key'


def fixture():
    return json.loads(Path(__file__).with_name('physical-same-key-unit-fixture.json').read_text())['records']


class PhysicalSameKeyTests(unittest.TestCase):
    def test_complete_native_fixture(self):
        result = p.validate_local(fixture(), RUN)
        self.assertEqual(len(result['marker_owners']), 7)
        self.assertTrue(result['physical_display_proof_still_required'])

    def test_rejects_missing_stale_late_or_changed_topology(self):
        for case in ['no-admission', 'no-before', 'late-before', 'background', 'hidden', 'alias', 'generation',
                     'nonce', 'capture', 'hash', 'late-loss', 'wrong-run', 'old-manifest', 'terminal-only']:
            with self.subTest(case=case):
                rows = fixture()
                signals = [r['signal'] for r in rows if r['type'] == 'signal']
                admitted = next(s for s in signals if s.get('name') == 'physical-topology-admitted')
                before = next(s for s in signals if s.get('name') == 'physical-topology-before-6')
                later = next(s for s in signals if s.get('name') == 'physical-topology-before-14')
                if case == 'no-admission': admitted['name'] = 'unqualified'
                elif case == 'no-before': before['name'] = 'missing'
                elif case == 'late-before': before['name'], later['name'] = later['name'], before['name']
                elif case == 'background': later['physicalTopology']['scenes'][0]['activationState'] = 'background'
                elif case == 'hidden': later['physicalTopology']['scenes'][0]['hidden'] = True
                elif case == 'alias': later['physicalTopology']['scenes'][0]['nativeSceneID'] = later['physicalTopology']['scenes'][1]['nativeSceneID']
                elif case == 'generation': later['physicalTopology']['scenes'][0]['generation'] += 1
                elif case == 'nonce': later['physicalTopology']['nonce'] = 'reused'
                elif case == 'capture': later['physicalTopology']['captureID'] = 'other'
                elif case == 'hash': later['physicalTopology']['evidenceSHA256'] = '0'*64
                elif case == 'late-loss': later['result'] = 'INCONCLUSIVE'
                elif case == 'wrong-run': before['runID'] = 'old'
                elif case == 'old-manifest': rows[0]['manifest']['scenario']['steps'].pop()
                elif case == 'terminal-only':
                    for s in signals: s.pop('physicalTopology', None)
                with self.assertRaises(Rejected): p.validate_local(rows, RUN)

    def test_rejects_wrong_compose_or_returned_owner(self):
        for case in ['peer-compose', 'after-peer-stop', 'resource', 'home', 'source', 'extra-marker']:
            with self.subTest(case=case):
                rows = fixture()
                signals = [r['signal'] for r in rows if r['type'] == 'signal']
                def event(phase, kind='rum-action'):
                    return next(s for s in signals if s.get('kind') == kind and s.get('name') == phase)
                a = event(p.PHASES[2]); b = event(p.PHASES[3]); after = event(p.PHASES[5])
                if case == 'peer-compose': b['rumContext']['viewID'] = a['rumContext']['viewID']
                elif case == 'after-peer-stop': after['rumContext']['viewID'] = b['rumContext']['viewID']
                elif case == 'resource': event(p.PHASES[2], 'rum-resource')['rumContext']['viewID'] = b['rumContext']['viewID']
                elif case == 'home': event(p.PHASES[6])['rumContext']['viewID'] = event(p.PHASES[0])['rumContext']['viewID']
                elif case == 'source': after['sourceContext']['nativeSceneID'] = 'foreign'
                elif case == 'extra-marker':
                    other = next(s for s in signals if s.get('kind') == 'rum-action' and not s.get('name','').startswith('same-key-'))
                    other['name'] = p.PHASES[2]
                with self.assertRaises(Rejected): p.validate_local(rows, RUN)

    def test_display_requires_exact_hashed_continuous_physical_evidence(self):
        rows = fixture()
        with tempfile.TemporaryDirectory() as tmp:
            shot, video = Path(tmp)/'shot.png', Path(tmp)/'capture.mp4'
            shot.write_bytes(b'unit-display-fixture'); video.write_bytes(b'unit-video-fixture')
            for r in rows:
                if r.get('signal', {}).get('physicalTopology'):
                    r['signal']['physicalTopology']['evidenceSHA256'] = hashlib.sha256(shot.read_bytes()).hexdigest()
            local = p.validate_local(rows, RUN); top = local['admission']['physicalTopology']
            proof = dict(run_id=RUN, device_reality='physical', capture_id=top['captureID'], nonce=top['nonce'],
                         visible_native_scenes=local['native_scenes'], visibility_review='both-window-content-visible-through-critical-interval',
                         screenshot=dict(path=str(shot),sha256=top['evidenceSHA256'],captured_at_ms=local['admission']['timestampMilliseconds']-1),
                         video=dict(path=str(video),sha256=hashlib.sha256(video.read_bytes()).hexdigest(),start_ms=1,end_ms=local['critical_end']['timestampMilliseconds']+1))
            proof['process_id'] = 123
            proof['challenge'] = dict(runID=RUN, scenarioID=p.SCENARIO, nonce=top['nonce'], processID=123, createdAtMilliseconds=1)
            proof['receipt'] = dict(proof['challenge'], capturedAtMilliseconds=proof['screenshot']['captured_at_ms'],
                                    captureID=top['captureID'], evidenceSHA256=top['evidenceSHA256'],
                                    nativeSceneIDs=local['native_scenes'], generations={s['logicalSceneID']: s['generation'] for s in top['scenes']})
            self.assertEqual(p.validate_display(local, RUN, proof)['state'], 'PASS')
            for case in ['run', 'device', 'late-shot', 'late-video', 'early-end', 'hash', 'visibility', 'before-challenge', 'receipt-time', 'process']:
                bad=copy.deepcopy(proof)
                if case=='run':bad['run_id']='old'
                elif case=='device':bad['device_reality']='simulated'
                elif case=='late-shot':bad['screenshot']['captured_at_ms']=bad['video']['end_ms']
                elif case=='late-video':bad['video']['start_ms']=bad['video']['end_ms']
                elif case=='early-end':bad['video']['end_ms']=1
                elif case=='hash':bad['screenshot']['sha256']='0'*64
                elif case=='before-challenge':bad['challenge']['createdAtMilliseconds']=bad['video']['end_ms']
                elif case=='receipt-time':bad['receipt']['capturedAtMilliseconds']=1
                elif case=='process':bad['receipt']['processID']=124
                else:bad['visibility_review']='capability-only'
                with self.subTest(case=case), self.assertRaises(Rejected):p.validate_display(local,RUN,bad)

    def test_complete_backend_inventory_rejects_wrong_owner_and_extra_work(self):
        local=p.validate_local(fixture(),RUN); rows=[]
        def emit(kind, view_id=None, event_id=None, name=None, phase=None, scene=None):
            c=dict(type=kind,session=dict(id=local['session_id']),context=dict(probe=dict(run_id=RUN,phase=phase,source_scene=scene)))
            if view_id:c['view']=dict(id=view_id,name=name)
            if event_id:c[kind]=dict(id=event_id)
            rows.append(dict(id=str(len(rows)),attributes=dict(custom=c)))
        for v in local['views']:emit('view',v['view_id'],name=v['name'])
        for w in local['work']:emit(w['kind'],w['view_id'],w['event_id'],phase=w['phase'],scene=w['source_scene'])
        self.assertEqual(p.validate_backend(local,RUN,rows,len(rows))['state'],'PASS')
        for case in ['count','missing','duplicate','owner','run','extra','error']:
            bad=copy.deepcopy(rows);count=len(bad)
            if case=='count':count+=1
            elif case=='missing':bad.pop();count-=1
            elif case=='duplicate':bad[-1]['id']=bad[0]['id']
            elif case=='owner':bad[-1]['attributes']['custom']['view']['id']='foreign'
            elif case=='run':bad[-1]['attributes']['custom']['context']['probe']['run_id']='old'
            elif case=='extra':bad[-1]['attributes']['custom'][bad[-1]['attributes']['custom']['type']]['id']='foreign'
            else:bad[-1]['attributes']['custom']['type']='error'
            with self.subTest(case=case),self.assertRaises(Rejected):p.validate_backend(local,RUN,bad,count)


if __name__ == '__main__':unittest.main()

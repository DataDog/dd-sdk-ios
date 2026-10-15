import copy
import math
import unittest
from contract import Invalid, compare_pair, compare_abba, number, slope

class ComparisonControls(unittest.TestCase):
    def sample(self,arm='A'):
        return dict(arm=arm,fps=60,hitch_ratio=0.002,max_hitch_seconds=0.02,max_hang_seconds=0,cpu_cores=0.1,idle_memory_bytes=100*1024**2,idle_slope_bytes_per_second=0)
    def test_positive_pair(self): self.assertEqual(compare_pair(self.sample(),self.sample())['state'],'PASS')
    def test_regressions_are_not_hidden(self):
        changes={'fps':56,'hitch_ratio':0.013,'max_hitch_seconds':0.25,'max_hang_seconds':0.25,'cpu_cores':0.121,'idle_memory_bytes':111*1024**2,'idle_slope_bytes_per_second':0.11*1024**2}
        for name,value in changes.items():
            with self.subTest(name=name):
                candidate=self.sample();candidate[name]=value
                self.assertEqual(compare_pair(self.sample(),candidate)['state'],'FAIL')
    def test_invalid_metrics(self):
        for value in [None,True,float('nan'),float('inf'),-1]:
            with self.subTest(value=value), self.assertRaises(Invalid):number(value,'test')
    def test_bad_baseline_is_invalid(self):
        baseline=self.sample();baseline['max_hang_seconds']=0.25
        with self.assertRaises(Invalid):compare_pair(baseline,self.sample())
    def test_positive_abba(self):self.assertEqual(compare_abba([self.sample(a) for a in ['A','B','B','A']])['state'],'PASS')
    def test_pair_order(self):
        with self.assertRaises(Invalid):compare_abba([self.sample(a) for a in ['A','B','A','B']])
    def test_one_pair_fail_is_not_averaged_away(self):
        rows=[self.sample(a) for a in ['A','B','B','A']];rows[2]['fps']=50
        self.assertEqual(compare_abba(rows)['state'],'FAIL')
    def test_repeat_memory_trend(self):
        rows=[self.sample(a) for a in ['A','B','B','A']];rows[2]['idle_memory_bytes']+=6*1024**2
        result=compare_abba(rows);self.assertTrue(all(p['state']=='PASS' for p in result['pairs']));self.assertEqual(result['state'],'FAIL')
    def test_slope(self):self.assertAlmostEqual(slope([(x,1000+x*2) for x in range(20)]),2)
    def test_partial_idle_is_invalid(self):
        for samples in [[(x,1000) for x in range(19)],[(x*2,1000) for x in range(20)]]:
            with self.assertRaises(Invalid):slope(samples)

if __name__=='__main__':unittest.main()

class NativeScenarioControls(unittest.TestCase):
    """Synthetic clock/counter rows exercise the oracle, not native performance."""
    def fixture(self):
        expected = dict(run_id='15c3ab11-af67-4f38-a77e-0682759504cc',
                        nonce='94c61177-b149-43f8-977c-3b9c18fae953', source='a'*40,
                        fixture='b'*64, framework='UIKit', pid=778)
        rows = []
        def add(kind, at, phase, **fields):
            rows.append(dict(kind=kind, uptime_ns=round(at*1e9), phase=phase, **fields))
        def boundary(at, phase, cycle, step):
            add('boundary', at, phase, cycle=cycle, step=str(step), scene='scene', window='window',
                width=400,height=800,screen_id='internal-screen',screen_count=1,screen_width=400,screen_height=800,scale=3,maximum_fps=120,
                windows=[dict(owned=True,key=True,hidden=False,root='UINavigationController'),
                         dict(owned=False,key=False,hidden=True,root='AuxiliaryController')])
        add('launch',99,'launch',**expected)
        add('admission',99.8,'launch',state='TRACE_READY',**expected)
        boundary(99.9,'launch',-1,'ready')
        start=100
        for phase,seconds,cycles in [('warmup',16,2),('active',96,12),('idle',30,0)]:
            add('phase-begin',start,phase,name=phase)
            for at,role in [(start+0.001,'begin')]+[(start+i+0.5,'periodic') for i in range(seconds)]+[(start+seconds-0.001,'end')]:
                add('sample',at,phase,sample_role=role,cpu_seconds=at*0.1,footprint_bytes=100*1024**2,thermal=0,low_power=False)
            for cycle in range(cycles):
                for step in range(8):boundary(start+cycle*8+step+0.8,phase,cycle,step)
                for step in [2,4]:add('view',start+cycle*8+step+0.81,phase,id=f'{phase}-{cycle}-{step}')
            add('phase-end',start+seconds,phase,name=phase)
            start+=seconds+0.01
        boundary(start,'transition',12,'terminal')
        add('terminal',start+0.001,'transition',state='SCENARIO_COMPLETE')
        rows.sort(key=lambda r:r['uptime_ns'])
        for i,row in enumerate(rows,1):row['sequence']=i
        return dict(schema_version=1,**expected,records=rows),expected

    def validate(self, document, expected):
        from contract import scenario
        return scenario(document,expected)

    def test_complete_native_workload_with_auxiliary_window(self):
        result=self.validate(*self.fixture())
        self.assertEqual(set(result),{'warmup','active','idle'})
        self.assertAlmostEqual(result['active']['cpu_cores'],0.1)

    def test_wrong_source_fixture_run_nonce_or_process(self):
        for field in ['source','fixture','run_id','nonce','pid','framework']:
            with self.subTest(field=field), self.assertRaises(Invalid):
                document,expected=self.fixture();document[field]='wrong';self.validate(document,expected)

    def test_stale_launch_identity(self):
        document,expected=self.fixture();document['records'][0]['pid']+=1
        with self.assertRaises(Invalid):self.validate(document,expected)

    def test_missing_or_reordered_native_boundary(self):
        for change in ['delete','reorder']:
            document,expected=self.fixture();row=next(r for r in document['records'] if r['kind']=='boundary')
            if change=='delete':document['records'].remove(row)
            else:row['step']='1'
            for i,r in enumerate(document['records'],1):r['sequence']=i
            with self.subTest(change=change),self.assertRaises(Invalid):self.validate(document,expected)

    def test_boundary_sample_roles(self):
        for role in ['begin','end']:
            document,expected=self.fixture();row=next(r for r in document['records'] if r.get('sample_role')==role);row['sample_role']='periodic'
            with self.subTest(role=role),self.assertRaises(Invalid):self.validate(document,expected)

    def test_sample_outside_phase_or_late_boundary(self):
        for offset in [-0.01,0.11]:
            document,expected=self.fixture();row=next(r for r in document['records'] if r.get('sample_role')=='begin')
            row['uptime_ns']=round((100+offset)*1e9)
            document['records'].sort(key=lambda r:r['uptime_ns'])
            for i,r in enumerate(document['records'],1):r['sequence']=i
            with self.subTest(offset=offset),self.assertRaises(Invalid):self.validate(document,expected)

    def test_missing_periodic_coverage(self):
        document,expected=self.fixture()
        document['records']=[r for r in document['records'] if not (r.get('sample_role')=='periodic' and 140e9<r['uptime_ns']<144e9)]
        for i,r in enumerate(document['records'],1):r['sequence']=i
        with self.assertRaises(Invalid):self.validate(document,expected)

    def test_counter_reversal_inside_and_between_phases(self):
        for crossing in [False,True]:
            document,expected=self.fixture();samples=[r for r in document['records'] if r['kind']=='sample' and r['phase']=='active']
            if crossing:
                for r in samples:r['cpu_seconds']-=2
            else:samples[3]['cpu_seconds']=0
            with self.subTest(crossing=crossing),self.assertRaises(Invalid):self.validate(document,expected)

    def test_nonfinite_or_empty_metrics(self):
        for field,value in [('cpu_seconds',float('nan')),('footprint_bytes',0),('footprint_bytes',True)]:
            document,expected=self.fixture();next(r for r in document['records'] if r['kind']=='sample')[field]=value
            with self.subTest(field=field,value=value),self.assertRaises(Invalid):self.validate(document,expected)

    def test_thermal_or_low_power(self):
        for field,value in [('thermal',1),('low_power',True)]:
            document,expected=self.fixture();next(r for r in document['records'] if r['kind']=='sample')[field]=value
            with self.subTest(field=field),self.assertRaises(Invalid):self.validate(document,expected)

    def test_background_and_metric_failures(self):
        for kind in ['inactive','disconnected','metric-failure','topology-failure','unexpected-callback']:
            document,expected=self.fixture();next(r for r in document['records'] if r['kind']=='view')['kind']=kind
            with self.subTest(kind=kind),self.assertRaises(Invalid):self.validate(document,expected)

    def test_display_geometry_and_owned_key_window(self):
        for change in ['geometry','foreign-key','missing-owner','external-display','partial-window','screen-identity']:
            document,expected=self.fixture();row=next(r for r in document['records'] if r['kind']=='boundary')
            if change=='geometry':row['screen_width']+=1
            elif change=='foreign-key':row['windows'][1]['key']=True
            elif change=='missing-owner':row['windows'][0]['owned']=False
            elif change=='external-display':row['screen_count']=2
            elif change=='partial-window':row['width']-=1
            else:row['screen_id']='other-screen'
            with self.subTest(change=change),self.assertRaises(Invalid):self.validate(document,expected)

    def test_incomplete_terminal_and_sdk_workload(self):
        for change in ['terminal','views']:
            document,expected=self.fixture()
            if change=='terminal':document['records'][-1]['state']='INVALID'
            else:
                for row in document['records']:
                    if row['kind']=='view':row['id']='one-view'
            with self.subTest(change=change),self.assertRaises(Invalid):self.validate(document,expected)

    def test_missing_foreign_or_late_recorder_admission(self):
        for change in ['missing','foreign','late']:
            document,expected=self.fixture();row=next(r for r in document['records'] if r['kind']=='admission')
            if change=='missing':document['records'].remove(row)
            elif change=='foreign':row['nonce']='stale'
            else:row['uptime_ns']=100_000_000_000
            document['records'].sort(key=lambda r:r['uptime_ns'])
            for i,r in enumerate(document['records'],1):r['sequence']=i
            with self.subTest(change=change),self.assertRaises(Invalid):self.validate(document,expected)

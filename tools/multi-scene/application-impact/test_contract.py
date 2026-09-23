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

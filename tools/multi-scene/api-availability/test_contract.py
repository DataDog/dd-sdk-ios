import copy
import unittest
from contract import validate, CALLS


def positive():
    receipt=dict(run_id='run',source='source',pid=123,os='17.5',automatic='off',callbacks=2,scene_unchanged=True,owned_window=True,
        preflight={'ready':True,'at':1,'automatic_owner':None},scene_reads_after_main_turn=0,
        main={'valid':True,'calls':CALLS.copy()},background={'onMain':False,'nilFactory':True,'rejectedUnreadScene':True,
            'sceneReads':0,'releasedScene':True,'calls':CALLS.copy()})
    events=[]
    for lane in ['swift-legacy','swift-targeted','objc-main','guard']:
        name=lane+'-manual' if lane=='objc-main' else lane
        context=dict(lane=lane,stop=2,start=1)
        context.update({'keep-single':'single' if lane=='guard' else 'value','keep-batch':'batch' if lane=='guard' else 7,'objc-main':'objc-main'})
        events.append(dict(type='view',view={'id':lane,'name':name,'is_active':False,'custom_timings':{'ready':1},'loading_time':1},
                           _dd={'document_version':1},context=context,feature_flags={'flag':True,'objc-main':True}))
        if lane=='guard':
            events.append(dict(type='action',view={'id':lane},context={'lane':lane},action={'target':{'name':'guard-ended'}}));continue
        for form in (['message','error'] if lane=='objc-main' else ['message','error','callback']): events.append(dict(type='error',view={'id':lane},context={'lane':lane,'form':form}))
        for form,method in [('request','GET'),('url','GET'),('method','PUT')]: events.append(dict(type='resource',view={'id':lane},context={'lane':lane,'finish':3,'form':form},resource={'method':method,'status_code':200,'url':'https://fixture.invalid/'+('objc-main' if lane=='objc-main' else 'resource')}))
        for name in (['objc-main','objc-main-ended'] if lane=='objc-main' else ['instant','ended']): events.append(dict(type='action',view={'id':lane},context={'lane':lane},action={'target':{'name':name}}))
        for step,failure in [('start',None),('end',None),('end','error')]:
            events.append(dict(type='vital',view={'id':lane},context={'lane':lane},vital={'type':'operation_step','step_type':step,'failure_reason':failure,'name':'objc-main' if lane=='objc-main' else 'operation','operation_key':lane if failure is None else lane+('-failed' if lane=='objc-main' else '-failure')}))
    receipt['pre_background']={'run_id':'run','nonce':'nonce','event_count':len(events)-2}
    return receipt,events


class OracleTests(unittest.TestCase):
    def check(self, receipt, events): return validate(receipt,events,'run','source','off',123,'17.5')
    def test_positive(self): self.assertEqual(self.check(*positive())['verdict'],'PASS')
    def test_automatic_name_matches_default_predicate(self):
        r,e=positive();r['automatic']='on';r['preflight']['automatic_owner']='automatic'
        e.insert(0,dict(type='view',view={'id':'automatic','name':'APIClient.FixtureScreen'}))
        r['pre_background']['event_count']+=1
        self.assertEqual(validate(r,e,'run','source','on',123,'17.5')['verdict'],'PASS')
        e[0]['view']['name']='FixtureScreen'
        with self.assertRaises(ValueError):validate(r,e,'run','source','on',123,'17.5')
    def test_rejects_missing_selector(self):
        r,e=positive();r['background']['calls'].pop()
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_stale_identity(self):
        for field,value in [('run_id','old'),('source','old'),('pid',122)]:
            r,e=positive();r[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_late_read_and_retention(self):
        for field,value in [('scene_reads_after_main_turn',1),('callbacks',1)]:
            r,e=positive();r[field]=value
            with self.subTest(field=field),self.assertRaises(ValueError):self.check(r,e)
        r,e=positive();r['background']['releasedScene']=False
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_foreign_owner_and_duplicate(self):
        r,e=positive();next(x for x in e if x['type']=='resource')['view']['id']='foreign'
        with self.assertRaises(ValueError):self.check(r,e)
        r,e=positive();e.append(copy.deepcopy(next(x for x in e if x['type']=='resource')))
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_off_main_telemetry(self):
        r,e=positive();e[0]['context']['unexpected']='off-main'
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_removed_guard_attribute(self):
        r,e=positive();next(x for x in e if x.get('view',{}).get('name')=='guard')['context']['keep-single']='bad'
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_untagged_background_event(self):
        r,e=positive();e.append(dict(type='error',view={'id':'guard'},context={}))
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_unrelated_background_long_task(self):
        r,e=positive();e.append(dict(type='long_task',view={'id':'guard'},context={'lane':'guard'}))
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_wrong_event_name(self):
        r,e=positive();next(x for x in e if x['type']=='action')['action']['target']['name']='foreign'
        with self.assertRaises(ValueError):self.check(r,e)
    def test_rejects_missing_precritical_owner(self):
        r,e=positive();r['preflight']['ready']=False
        with self.assertRaises(ValueError):self.check(r,e)


if __name__=='__main__':unittest.main()

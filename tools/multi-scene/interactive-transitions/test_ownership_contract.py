import copy
import unittest
from unittest.mock import patch
import ownership_contract as c


def cell():
    result={}
    for phase in ['pop.finish','pop.cancel','dismiss.finish','dismiss.cancel']:
        before=dict(id='outgoing-'+phase,name='detail',path='local-a',session='session',mapper_sequence=2)
        after=dict(before) if phase.endswith('cancel') else dict(id='return-'+phase,name='home',path='local-b',session='session',mapper_sequence=3)
        result[phase]=dict(before=[before],after=[after],callback_snapshot=[after],callback=dict(view=after['id']),
            relation='preserved' if phase.endswith('cancel') else 'fresh',semantic_expectation='PASS')
    return result


class PairedOwners(unittest.TestCase):
    def test_uuids_and_manual_process_paths_are_not_cross_run_keys(self):
        a=cell();b=copy.deepcopy(a)
        for phase,value in b.items():
            changed=set()
            for key in ['before','after','callback_snapshot']:
                for owner in value[key]:
                    if id(owner) in changed:continue
                    changed.add(id(owner));owner['id']='candidate-'+owner['id'];owner['path']='different-process-path'
            value['callback']['view']='candidate-'+value['callback']['view']
        result=c.paired(a,b,tracking='manual')
        self.assertEqual(result['state'],'PAIRED_OWNER_PATTERN_MATCH_REQUIRES_CLASSIFICATION');self.assertFalse(result['release_acceptance'])
    def test_automatic_path_change_is_not_a_manual_hash_exception(self):
        a=cell();b=copy.deepcopy(a);b['pop.finish']['after'][0]['path']='changed-path'
        with self.assertRaises(ValueError):c.paired(a,b,tracking='automatic')
    def test_fresh_owner_after_cancel_cannot_pass_as_same_name(self):
        a=cell();b=copy.deepcopy(a);b['pop.cancel']['relation']='fresh';b['pop.cancel']['semantic_expectation']='FAIL'
        with self.assertRaises(ValueError):c.paired(a,b,tracking='manual')
    def test_missing_or_extra_phase_rejected(self):
        a=cell();b=cell();del b['dismiss.cancel']
        with self.assertRaises(ValueError):c.paired(a,b,tracking='manual')
    def test_callback_foreign_owner_rejected(self):
        a=cell();b=cell();b['dismiss.finish']['callback']['view']='foreign'
        with self.assertRaises(ValueError):c.paired(a,b,tracking='manual')
    def test_inherited_limitation_stays_failed_and_requires_classification(self):
        a=cell();b=cell()
        for value in [a,b]:value['pop.cancel'].update(relation='fresh',semantic_expectation='FAIL')
        result=c.paired(a,b,tracking='manual')
        self.assertEqual(result['inherited_limitations'],['pop.cancel']);self.assertFalse(result['release_acceptance'])

class ActualCallbackSide(unittest.TestCase):
    def test_wrong_side_is_an_explicit_semantic_failure_even_when_views_are_correct(self):
        for cancelled in [False,True]:
            a=dict(id='old',name='detail',path='path',session='session',mapper_sequence=1)
            b=dict(a) if cancelled else dict(id='new',name='home',path='home',session='session',mapper_sequence=2)
            callback=dict(view='foreign' if cancelled else 'old',session='session')
            result=dict(cancelled=cancelled,transition_id='native',callback_id='callback',completion_sequence=3)
            rows=[dict(sequence=3,kind='transition_complete',payload=dict(callback_id='callback'))]
            with patch.object(c,'owners',side_effect=[[a],[b],[b]]),patch.object(c.native,'callback_work',return_value=callback):
                value=c.transition_owners(rows,{}, {},result)
            self.assertEqual(value['semantic_expectation'],'FAIL');self.assertFalse(value['callback_owner_matches'])
    def test_correct_action_cannot_repair_missing_foreign_or_late_callback_owner(self):
        a=dict(id='old',name='detail',path='path',session='session',mapper_sequence=1)
        b=dict(id='new',name='home',path='home',session='session',mapper_sequence=2)
        result=dict(cancelled=False,transition_id='native',callback_id='callback',completion_sequence=3)
        rows=[dict(sequence=3,kind='transition_complete',payload=dict(callback_id='callback'))]
        for snapshot in [[],[a],[dict(b,mapper_sequence=4)]]:
            with patch.object(c,'owners',side_effect=[[a],[b],snapshot]),patch.object(c.native,'callback_work',return_value=dict(view='new',session='session')):
                value=c.transition_owners(rows,{}, {},result)
            self.assertEqual(value['semantic_expectation'],'FAIL');self.assertFalse(value['callback_boundary_matches'])
    def test_right_side_callback_retains_semantic_success(self):
        a=dict(id='old',name='detail',path='path',session='session',mapper_sequence=1)
        b=dict(id='new',name='home',path='home',session='session',mapper_sequence=2)
        result=dict(cancelled=False,transition_id='native',callback_id='callback',completion_sequence=3)
        rows=[dict(sequence=3,kind='transition_complete',payload=dict(callback_id='callback'))]
        with patch.object(c,'owners',side_effect=[[a],[b],[b]]),patch.object(c.native,'callback_work',return_value=dict(view='new',session='session')):
            value=c.transition_owners(rows,{}, {},result)
        self.assertEqual(value['semantic_expectation'],'PASS');self.assertTrue(value['callback_owner_matches'])


def complete_inventory():
    views={x:dict(event=dict(view=dict(id=x,name=x,url=x,is_active=False,action=dict(count=2)))) for x in ['one','two']}
    callbacks={phase:dict(callback_id=phase+'-id') for phase in ['pop.finish','pop.cancel','dismiss.finish','dismiss.cancel']}
    accepted={}
    for index,(phase,callback) in enumerate(callbacks.items()):
        event=dict(type='action',view=dict(id='one' if index<2 else 'two'),
            action=dict(id=phase,type='custom',target=dict(name='transition.callback')),
            context=dict(transition_callback=callback['callback_id']))
        accepted[('action',phase)]=dict(event=event)
    return dict(views=views,occurrence_order=['one','two'],accepted=accepted),callbacks


class CompleteInventories(unittest.TestCase):
    def compare(self,a,b,ca,cb):return c.paired_inventory(a,b,ca,cb,tracking='automatic')
    def test_all_events_match_without_backend_credit(self):
        a,ca=complete_inventory();b,cb=complete_inventory()
        result=self.compare(a,b,ca,cb);self.assertEqual(result['non_view_count'],4);self.assertFalse(result['release_acceptance'])
    def test_extra_candidate_automatic_action_rejected(self):
        a,ca=complete_inventory();b,cb=complete_inventory()
        b['accepted'][('action','extra')]=dict(event=dict(type='action',view=dict(id='one'),action=dict(type='tap',id='extra',target=dict(name='extra'))))
        with self.assertRaises(ValueError):self.compare(a,b,ca,cb)
    def test_missing_duplicate_callback_rejected(self):
        a,ca=complete_inventory();b,cb=complete_inventory();b['accepted'][('action','extra')]=copy.deepcopy(next(iter(b['accepted'].values())))
        with self.assertRaises(ValueError):self.compare(a,b,ca,cb)
    def test_wrong_existing_owner_rejected(self):
        a,ca=complete_inventory();b,cb=complete_inventory();next(iter(b['accepted'].values()))['event']['view']['id']='two'
        with self.assertRaises(ValueError):self.compare(a,b,ca,cb)
    def test_terminal_counter_change_rejected(self):
        a,ca=complete_inventory();b,cb=complete_inventory();b['views']['one']['event']['view']['action']['count']=3
        with self.assertRaises(ValueError):self.compare(a,b,ca,cb)



class SplitInventory(unittest.TestCase):
    def test_split_has_no_synthetic_callback_requirement(self):
        a,_=complete_inventory();a['accepted']={};b=copy.deepcopy(a)
        result=c.paired_inventory(a,b,{}, {},tracking='manual',layout='split');self.assertEqual(result['non_view_count'],0)
    def test_unplanned_split_callback_rejected(self):
        a,callbacks=complete_inventory()
        with self.assertRaises(ValueError):c.paired_inventory(a,a,callbacks,callbacks,tracking='manual',layout='split')
    def test_new_occurrence_after_fold_does_not_pass_same_name(self):
        owner=dict(id='a',name='detail',path='process-hash')
        a=[dict(phase=p,ownership=c.adaptive_owners([owner],[owner])) for p in ['open','close','reopen']]
        b=copy.deepcopy(a);b[1]['ownership']=c.adaptive_owners([owner],[dict(owner,id='new')])
        with self.assertRaises(ValueError):c.paired_adaptive(a,b,tracking='manual')

if __name__=='__main__':unittest.main()

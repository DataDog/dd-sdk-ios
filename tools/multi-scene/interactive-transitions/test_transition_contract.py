import copy
import unittest
import transition_contract as c


def sample(cancelled=False):
    phase = 'pop.cancel.before' if cancelled else 'pop.finish.before'
    recognizer = dict(id='pan', view='gesture-view', window='window', delegate='framework', enabled=True,
                      cancels_touches=True, delays_began=False, delays_ended=True, exclusive_touch=True,
                      touch_types=[0], press_types=[], minimum_touches=1, maximum_touches=1, edges=2)
    graph = [dict(id=x, window='window', children=[]) for x in ['detail', 'home']]
    before = dict(sequence=3, kind='human_snapshot', payload=dict(request_id='request', phase=phase, uptime_ns=10,
        transition=dict(armed=[recognizer], controllers=graph, model=dict(path=['detail']))))
    after = dict(sequence=9, kind='human_snapshot', payload=dict(request_id='effect',
        phase=phase.removesuffix('.before')+'.effect', uptime_ns=20,
        transition=dict(controllers=graph, model=dict(path=['detail'] if cancelled else []))))
    rows = [dict(sequence=2, kind='transition_armed', payload=dict(request_id='request', phase=phase, recognizers=[recognizer])), before]
    common = dict(transition_id='transition', coordinator='coordinator', request_id='request', current_request_id='request',
                  phase=phase, window='window', scene='scene', initially_interactive=True, percent_complete=.2,
                  **{'from':'detail', 'to':'home'})
    for seq, kind, extra in [
        (4,'transition_begin',dict(interactive=True,cancelled=False,recognizer=recognizer,recognizer_state=1)),
        (5,'transition_registered',dict(interactive=True,cancelled=False,duration_ns=1_000,animations_queued=True)),
        (6,'transition_change',dict(interactive=False,cancelled=cancelled)),
        (7,'transition_complete',dict(interactive=False,cancelled=cancelled,callback_id='callback'))]:
        rows.append(dict(sequence=seq,kind=kind,payload=dict(common,uptime_ns=seq+10,**extra)))
    rows += [dict(sequence=8,kind='transition_closed',payload=dict(request_id='request',phase=phase,reason='completion',
        configuration_unchanged=True,recognizers=[recognizer],terminal_recognizers=[copy.deepcopy(recognizer)])), after]
    return rows, before, after


class NativeTransitions(unittest.TestCase):
    def check(self, rows, before, after, cancelled=False):
        return c.transition(rows,before,after,cancelled=cancelled,binding=dict(window='window',scene='scene'))
    def test_finish_and_cancel_have_real_distinct_results(self):
        for cancelled in [False,True]:
            values=sample(cancelled);result=self.check(*values,cancelled)
            self.assertEqual(result['result'],'detail' if cancelled else 'home')
            self.assertEqual(result['ownership'],'REQUIRES_INDEPENDENT_MAPPER_AND_BACKEND_CLASSIFICATION')
    def test_absent_or_duplicate_native_callback_rejected(self):
        for kind in ['transition_begin','transition_registered','transition_change','transition_complete','transition_closed']:
            for duplicate in [False,True]:
                rows,a,b=sample();row=next(x for x in rows if x['kind']==kind)
                if duplicate:rows.insert(1,copy.deepcopy(row))
                else:rows.remove(row)
                with self.subTest(kind=kind,duplicate=duplicate),self.assertRaises(ValueError):self.check(rows,a,b)
    def test_completion_only_false_animation_result_is_not_false_failure(self):
        rows,a,b=sample();rows[3]['payload']['animations_queued']=False
        self.check(rows,a,b)
        rows.remove(rows[5])
        with self.assertRaises(ValueError):self.check(rows,a,b)
    def test_late_registration_rejected(self):
        rows,a,b=sample();rows[3]['sequence']=6.5
        with self.assertRaises(ValueError):self.check(rows,a,b)
    def test_noninteractive_and_wrong_state_rejected(self):
        for key,value in [('interactive',False),('initially_interactive',False),('recognizer_state',2)]:
            rows,a,b=sample();rows[2]['payload'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):self.check(rows,a,b)
    def test_foreign_or_consumed_transition_rejected(self):
        for key in ['coordinator','window','scene','from','to','current_request_id']:
            rows,a,b=sample();rows[4]['payload'][key]='foreign'
            with self.subTest(key=key),self.assertRaises(ValueError):self.check(rows,a,b)
    def test_cancel_result_and_model_must_agree(self):
        rows,a,b=sample(True);b['payload']['transition']['model']['path']=[]
        with self.assertRaises(ValueError):self.check(rows,a,b,True)
        rows,a,b=sample();rows[5]['payload']['cancelled']=True
        with self.assertRaises(ValueError):self.check(rows,a,b)
    def test_clock_boundary_and_malformed_duration_rejected(self):
        for key,value,index in [('uptime_ns',9,4),('uptime_ns',100,5),('duration_ns',-1,3),('duration_ns',True,3),('duration_ns',None,3)]:
            rows,a,b=sample();rows[index]['payload'][key]=value
            with self.subTest(key=key,value=value),self.assertRaises(ValueError):self.check(rows,a,b)
    def test_registration_duration_is_diagnostic_for_both_native_outcomes(self):
        for cancelled in [False,True]:
            rows,a,b=sample(cancelled);rows[3]['payload']['duration_ns']=100_000_001
            self.assertEqual(self.check(rows,a,b,cancelled)['cancelled'],cancelled)
    def test_no_late_callback_or_missing_removal(self):
        rows,a,b=sample();rows.append(dict(sequence=10,kind='transition_observer_rejected',payload={}))
        with self.assertRaises(ValueError):self.check(rows,a,b)
    def test_framework_attachment_changes_are_retained_without_policy_waiver(self):
        rows,a,b=sample();end=rows[-2]['payload']['terminal_recognizers'][0]
        end['window']='nil';end['enabled']=False
        self.check(rows,a,b)
        end['delegate']='replacement'
        with self.assertRaises(ValueError):self.check(rows,a,b)
    def test_result_requires_actual_attached_controller(self):
        rows,a,b=sample();b['payload']['transition']['controllers']=[]
        with self.assertRaises(ValueError):self.check(rows,a,b)


def mapper():
    event=dict(type='view',view=dict(id='view',name='detail',url='process-local',is_active=True),
               session=dict(id='session'),_dd=dict(document_version=1),date=123)
    row=dict(sequence=1,kind='rum',payload=event)
    boundary=dict(sequence=2,payload=dict(mapper_views=[dict(sequence=1,view=copy.deepcopy(event['view']),
        session=event['session'],document=event['_dd'],date=event['date'])]))
    return [row],boundary


class MapperBoundaries(unittest.TestCase):
    def test_independent_atomic_owner(self):
        rows,b=mapper();self.assertEqual(c.active_owner(rows,b)[0]['event']['view']['id'],'view')
    def test_stale_or_substituted_snapshot(self):
        for key,value in [('sequence',0),('view',dict(id='other')),('document',dict(document_version=2)),('date',124)]:
            rows,b=mapper();b['payload']['mapper_views'][0][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):c.active_owner(rows,b)
    def test_complete_owner_inventory(self):
        rows,b=mapper();b['payload']['mapper_views']=[]
        with self.assertRaises(ValueError):c.active_owner(rows,b)
    def test_empty_automatic_coverage_is_not_synthesized(self):
        self.assertEqual(c.active_owner([],dict(sequence=1,payload=dict(mapper_views=[]))),[])
    def test_callback_action_after_actual_completion(self):
        native=dict(callback_id='callback',completion_sequence=7)
        row=dict(sequence=8,kind='rum',payload=dict(type='action',context=dict(transition_callback='callback'),
            action=dict(id='action',type='custom',target=dict(name='transition.callback')),view=dict(id='view'),session=dict(id='session')))
        self.assertEqual(c.callback_work([row],native)['view'],'view')
        row['sequence']=6
        with self.assertRaises(ValueError):c.callback_work([row],native)

if __name__=='__main__':unittest.main()

import copy
import json
import unittest

from acceptance_common import Rejected
import local_event_collection as collection


def encode(rows):
    return b''.join((json.dumps(row) + '\n').encode() for row in rows)


def row(sequence, kind, payload):
    if kind=='rum':
        payload.update(application={'id':'app'},service='fixture',source='ios')
        payload.setdefault('date',2);payload.setdefault('session',{'id':'session'})['type']='user'
    return dict(sequence=sequence, run_id='run', kind=kind, payload=payload)


def view(active, revision, count=1):
    return dict(type='view', date=1, session=dict(id='session'), _dd=dict(document_version=revision),
                view=dict(id='view', name='Home', url='Home', is_active=active, action=dict(count=count)))


def action():
    return dict(type='action', view=dict(id='view',name='Home',url='Home'), action=dict(id='action', type='tap'))


class HomeCollection(unittest.TestCase):
    def setUp(self):
        self.rows = [row(1, 'human_snapshot', {'phase':'background.before'}), row(2, 'rum', view(True, 1)),
                     row(3, 'native_background', {}), row(4, 'geometry', {})]
        # A real pre-Home snapshot follows the currently active View mapper.
        self.rows[0],self.rows[1]=self.rows[1],self.rows[0]
        for i,r in enumerate(self.rows,1):r['sequence']=i
        self.prefix = encode(self.rows)

    def check(self, rows, **kwargs):
        return collection.terminal_rows(encode(rows), run_id='run', prefix=self.prefix, **kwargs)

    def test_checkpoint_is_pending_until_the_delayed_stop_and_counted_action_arrive(self):
        self.assertIsNone(self.check(self.rows))
        stopped = self.rows + [row(5, 'rum', view(False, 2))]
        self.assertIsNone(self.check(stopped))
        complete = stopped + [row(6, 'rum', action())]
        self.assertEqual(self.check(complete), complete)
        self.assertEqual(encode(self.rows), self.prefix)

    def test_partial_tail_is_pending_never_silently_discarded(self):
        raw = encode(self.rows + [row(5, 'rum', action()), row(6, 'rum', view(False, 2))])
        self.assertIsNone(collection.terminal_rows(raw + b'{', run_id='run', prefix=self.prefix))

    def test_wrong_owner_is_incomplete_and_duplicate_action_is_invalid(self):
        complete = self.rows + [row(5, 'rum', action()), row(6, 'rum', view(False, 2))]
        wrong = copy.deepcopy(complete); wrong[4]['payload']['view']['id'] = 'foreign'
        self.assertIsNone(self.check(wrong))
        with self.assertRaises(Rejected): self.check(complete + [row(7, 'rum', action())])

    def test_native_activity_and_rewritten_prefix_reject(self):
        with self.assertRaises(Rejected): self.check(self.rows + [row(5, 'native_input', {})])
        changed = copy.deepcopy(self.rows); changed[0]['payload']['view']['name'] = 'other'
        with self.assertRaises(Rejected): self.check(changed)

    def test_changed_identity_missing_revision_foreign_run_and_bad_type_reject(self):
        complete = self.rows + [row(5, 'rum', action()), row(6, 'rum', view(False, 2))]
        for mode in ['identity', 'revision', 'run', 'counter']:
            changed = copy.deepcopy(complete)
            if mode == 'identity': changed[-1]['payload']['session']['id'] = 'foreign'
            elif mode == 'revision': changed[-1]['payload']['_dd']['document_version'] = 3
            elif mode == 'run': changed[-1]['run_id'] = 'old'
            else: changed[-1]['payload']['view']['action']['count'] = True
            with self.subTest(mode=mode), self.assertRaises(Rejected): self.check(changed)

    def test_exact_callback_set_is_required_independently_of_counts(self):
        event = action(); event['context'] = dict(transition_callback='callback')
        complete = self.rows + [row(5, 'rum', event), row(6, 'rum', view(False, 2))]
        self.assertEqual(self.check(complete, callbacks=['callback']), complete)
        self.assertIsNone(self.check(complete, callbacks=['callback', 'missing']))
        with self.assertRaises(Rejected): self.check(complete, callbacks=['other'])

    def test_balanced_old_views_do_not_replace_a_post_home_stop(self):
        self.rows[0]['payload']['view']['is_active']=False;self.rows[0]['payload']['view']['action']['count']=0
        self.prefix=encode(self.rows)
        self.assertIsNone(self.check(self.rows))

    def test_late_action_requires_the_new_inactive_counter_revision(self):
        complete=self.rows+[row(5,'rum',action()),row(6,'rum',view(False,2))]
        second=action();second['action']['id']='second'
        later=complete+[row(7,'rum',second)]
        self.assertIsNone(self.check(later))
        final=later+[row(8,'rum',view(False,3,2))]
        self.assertEqual(self.check(final),final)

    def test_matching_id_with_foreign_session_name_or_source_is_rejected(self):
        complete=self.rows+[row(5,'rum',action()),row(6,'rum',view(False,2))]
        for mode in ['session','name','url','source','session_type','application','service']:
            values=copy.deepcopy(complete);event=values[4]['payload']
            if mode=='session':event['session']['id']='foreign'
            elif mode=='name':event['view']['name']='foreign'
            elif mode=='url':event['view']['url']='foreign'
            elif mode=='session_type':event['session']['type']='synthetics'
            elif mode=='application':event['application']['id']='foreign'
            elif mode=='service':event['service']='foreign'
            else:event['source']='browser'
            with self.subTest(mode=mode),self.assertRaises(Rejected):self.check(values)

    def test_real_view_metadata_need_not_appear_on_action_events(self):
        # Saved physical capture: View owns locale/session activity while the
        # same occurrence's Action has only application ID and session ID/type.
        self.rows[0]['payload']['application']['current_locale']='fr-FR'
        self.rows[0]['payload']['session'].update(has_replay=False,is_active=True)
        self.prefix=encode(self.rows)
        stopped=row(6,'rum',view(False,2))
        stopped['payload']['application']['current_locale']='fr-FR'
        stopped['payload']['session'].update(has_replay=False,is_active=True)
        complete=self.rows+[row(5,'rum',action()),stopped]
        self.assertEqual(self.check(complete),complete)

    def test_session_activity_and_locale_changes_do_not_change_view_ownership(self):
        complete=self.rows+[row(5,'rum',action()),row(6,'rum',view(False,2))]
        complete[-1]['payload']['application']['current_locale']='fr-FR'
        complete[-1]['payload']['session'].update(has_replay=False,is_active=False)
        self.assertEqual(self.check(complete),complete)

    def test_new_active_owner_between_snapshot_and_home_is_collected(self):
        self.rows[0]['payload']['view'].update(is_active=False,action={'count':0})
        fresh=view(True,1,0);fresh['view']['id']='new'
        self.rows.insert(2,row(3,'rum',fresh))
        for i,r in enumerate(self.rows,1):r['sequence']=i
        self.prefix=encode(self.rows)
        self.assertIsNone(self.check(self.rows))
        stopped=copy.deepcopy(fresh);stopped['view']['is_active']=False;stopped['_dd']['document_version']=2
        final=self.rows+[row(6,'rum',stopped)]
        self.assertEqual(self.check(final),final)

    def test_queued_active_owner_after_home_also_needs_its_inactive_revision(self):
        self.rows[0]['payload']['view'].update(is_active=False,action={'count':0});self.prefix=encode(self.rows)
        fresh=view(True,1,0);fresh['view']['id']='new'
        active=self.rows+[row(5,'rum',fresh)]
        self.assertIsNone(self.check(active))
        stopped=copy.deepcopy(fresh);stopped['view']['is_active']=False;stopped['_dd']['document_version']=2
        final=active+[row(6,'rum',stopped)];self.assertEqual(self.check(final),final)


if __name__ == '__main__': unittest.main()

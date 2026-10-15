import json
import unittest
from test_validate import fixture
from validate import validate_rum_backend


def backend_fixture():
    receipt = fixture()
    observations = receipt['observations']
    session = observations['operations'][0]['sessionID']
    events = []

    def add(kind, **fields):
        event = {'type': kind, 'session': {'id': session},
                 'context': {'multiscene': {'run_id': receipt['runID']}},
                 '_dd': {'profiling': {'status': 'running'}}, 'profiling': {'has_profile': True}}
        event.update(fields)
        events.append({'id': 'event-' + str(len(events)), 'attributes': {'custom': event}})

    for view in observations['views']:
        value = {'id': view['id'], 'name': view['name'], 'is_active': False}
        value.update({field: {'count': 0} for field in ['action', 'resource', 'error', 'crash', 'long_task']})
        add('view', view=value)
    for op in observations['operations']:
        add('vital', vital={'type': 'operation_step', 'id': op['vital']['id'], 'name': op['vital']['name'],
                            'operation_key': op['operationKey'], 'step_type': op['step']},
            view={'id': op['viewID']})
    add('vital', vital={'type': 'app_launch', 'name': 'time_to_initial_display'})
    for start, end in [(observations['operations'][0], observations['operations'][3]),
                       (observations['operations'][1], observations['operations'][2])]:
        add('operation', vital={'id': start['vital']['id']},
            operation={'name': 'exp187.parallel', 'operation_key': start['operationKey'], 'status': 'success',
                       'start_view': {'id': start['viewID']}, 'end_view': {'id': end['viewID']}})
    add('session')
    return receipt, events


def response(rows):
    return '<count>12</count><JSON_DATA>' + json.dumps(rows) + '</JSON_DATA>'


COUNTS = '<TSV_DATA>@type\tcount\nvital\t5\nview\t4\noperation\t2\nsession\t1</TSV_DATA>'


class BackendValidationTests(unittest.TestCase):
    def test_complete_backend_with_independent_count_and_exhausted_page_passes(self):
        receipt, rows = backend_fixture()
        result = validate_rum_backend(receipt, response(rows), COUNTS, response([]))
        self.assertEqual(result['state'], 'PASS')
        self.assertEqual(result['unique_events'], 12)
        self.assertTrue(result['all_operation_steps_have_profile'])

    def test_wrong_ownership_stale_identity_and_incomplete_inventory_fail(self):
        for mutation in ['duplicate', 'partial', 'page', 'count', 'run', 'session', 'step_owner', 'key',
                         'step_id', 'aggregate_start', 'aggregate_end', 'collapsed', 'extra_telemetry',
                         'launch', 'view_name', 'active_view']:
            with self.subTest(mutation=mutation):
                receipt, rows = backend_fixture()
                get = lambda index: rows[index]['attributes']['custom']
                counts, end = COUNTS, response([])
                if mutation == 'duplicate':
                    rows[-1]['id'] = rows[0]['id']
                elif mutation == 'partial':
                    rows.pop()
                elif mutation == 'page':
                    end = response([rows[0]])
                elif mutation == 'count':
                    counts = counts.replace('vital\t5', 'vital\t6')
                elif mutation == 'run':
                    get(4)['context']['multiscene']['run_id'] += '-stale'
                elif mutation == 'session':
                    get(4)['session']['id'] = get(0)['view']['id']
                elif mutation == 'step_owner':
                    get(4)['view']['id'] = get(1)['view']['id']
                elif mutation == 'key':
                    get(4)['vital']['operation_key'] = get(5)['vital']['operation_key']
                elif mutation == 'step_id':
                    get(4)['vital']['id'] = get(5)['vital']['id']
                elif mutation == 'aggregate_start':
                    get(9)['operation']['start_view']['id'] = get(1)['view']['id']
                elif mutation == 'aggregate_end':
                    get(9)['operation']['end_view']['id'] = get(0)['view']['id']
                elif mutation == 'collapsed':
                    get(9)['operation']['operation_key'] = get(10)['operation']['operation_key']
                elif mutation == 'extra_telemetry':
                    get(0)['view']['error']['count'] = 1
                elif mutation == 'launch':
                    get(8)['vital']['name'] = 'unexpected'
                elif mutation == 'view_name':
                    get(0)['view']['name'] = 'wrong owner'
                else:
                    get(0)['view']['is_active'] = True
                with self.assertRaises(ValueError):
                    validate_rum_backend(receipt, response(rows), counts, end)

    def test_rum_ownership_does_not_certify_profile_attachment(self):
        receipt, rows = backend_fixture()
        for row in rows:
            row['attributes']['custom']['profiling']['has_profile'] = False
        result = validate_rum_backend(receipt, response(rows), COUNTS, response([]))
        self.assertEqual(result['state'], 'PASS')
        self.assertFalse(result['all_operation_steps_have_profile'])


if __name__ == '__main__':
    unittest.main()

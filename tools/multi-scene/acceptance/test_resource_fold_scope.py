"""Source-bound controls for the current fold measurement and transport contract."""
import ast
import copy
import hashlib
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch
from acceptance_common import Rejected
import resource_fold_runtime as runtime
import resource_fold_runtime_variant as variant
import resource_fold_scope as scope


def module(raw, name):
    result = types.ModuleType(name)
    exec(compile(raw, name+'.py', 'exec'), result.__dict__)
    return result


class ScopedFoldControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads(runtime.OWNER.read_text())['human_preparation']
        cls.origin = Path(cls.contract['original_root'])
        cls.manifest = json.loads((cls.origin/'matrix/helper-manifest.json').read_text())
        cls.raw = Path(cls.manifest['oracle']['path']).read_bytes()
        cls.projected = scope.render_oracle(cls.raw, cls.manifest['oracle']['sha256'])
        cls.oracle = module(cls.projected, 'scoped_oracle')
        cls.original = module(cls.raw, 'original_oracle')
        cls.fold_raw = (cls.origin/'host/fold_oracle.py').read_bytes()
        cls.fold_projection = variant.render('fold_oracle.py', cls.fold_raw,
            cls.contract['original_inputs']['host/fold_oracle.py'], semantic=True)
        cls.fold = module(cls.fold_projection, 'scoped_fold')

    def test_unaffected_semantic_and_backend_functions_are_identical(self):
        def functions(raw): return {n.name: ast.dump(n, include_attributes=False) for n in ast.parse(raw).body if isinstance(n, ast.FunctionDef)}
        before, after = functions(self.raw), functions(self.projected)
        self.assertEqual(before.keys(), after.keys())
        changed = {name for name in before if before[name] != after[name]}
        self.assertEqual(changed, {'evaluate_local', 'evaluate', 'validate_ttid', 'evaluate_backend', 'inventory_exchange'})
        before, after = functions(self.fold_raw), functions(self.fold_projection)
        self.assertEqual({name for name in before if before[name] != after[name]}, {'topology', 'evaluate', 'proof'})

    def test_changed_original_oracle_rejected(self):
        with self.assertRaises(Rejected): scope.render_oracle(self.raw+b'\n', self.manifest['oracle']['sha256'])

    def topology_record(self):
        path = max((self.origin/'cells/A-automatic/native-evidence').glob('*.json'), key=lambda p: p.stat().st_size)
        records = json.loads(path.read_text())['records']
        return copy.deepcopy(next(r for r in records if 'topology_json' in r))

    def test_slow_capture_is_diagnostic_but_keeps_real_topology(self):
        record = self.topology_record(); self.fold.geometry(record)
        record['capture_finished_ns'] = record['capture_started_ns']+3_000_000_000
        record['monotonic_ns'] = record['capture_finished_ns']+1
        self.fold.geometry(record)
        with self.assertRaisesRegex(ValueError, 'stalled atomic capture'):
            module(self.fold_raw, 'original_fold').geometry(record)

    def test_reversed_capture_clocks_still_rejected(self):
        record = self.topology_record(); record['capture_finished_ns'] = record['capture_started_ns']-1
        with self.assertRaisesRegex(ValueError, 'reversed capture clocks'): self.fold.geometry(record)

    def test_missing_owned_window_still_rejected(self):
        record = self.topology_record(); topology = json.loads(record['topology_json'])
        for scene in topology['scenes']:
            for window in scene['windows']: window['is_fixture_window'] = False
        record['topology_json'] = json.dumps(topology)
        record['topology_sha256'] = hashlib.sha256(record['topology_json'].encode()).hexdigest()
        with self.assertRaisesRegex(ValueError, 'owned window'): self.fold.geometry(record)

    def exchange(self):
        ident = {'run_id': 'fresh-run', 'nonce': 'fresh-nonce'}
        request = {'request_id': 'fresh-request', **ident, 'kind': 'rum-startup', 'query': 'exact query',
                   'from': 'from', 'to': 'to', 'gather_started_ms': 1000}
        response = {'provider': 'datadog-mcp', 'request_id': request['request_id'],
                    'request_sha256': self.oracle.digest(request), 'query': request['query'], 'complete': True,
                    'backend_interpretation_sha256': self.oracle.BACKEND_INTERPRETATION_SHA256,
                    'timing': {'gather_started_ms': 1000, 'deadline_ms': 116000, 'publication_checked_ms': 2000},
                    'aggregate_count': 1, 'pages': [{'cursor_in': None, 'cursor_out': None, 'rows': [{'id': 'actual-row'}]}]}
        return {'request': request, 'response': response}, ident

    def inventory(self, exchange, ident, oracle=None):
        return (oracle or self.oracle).inventory_exchange(exchange, 'rum-startup', 'exact query', {'from': 'from', 'to': 'to'}, ident)

    def test_published_request_schema_now_matches_final_evaluator(self):
        exchange, ident = self.exchange()
        with self.assertRaisesRegex(self.original.Rejected, 'request fields'): self.inventory(exchange, ident, self.original)
        self.assertEqual(self.inventory(exchange, ident), [{'id': 'actual-row'}])

    def test_missing_or_restored_request_clock_rejected(self):
        for replacement in [None, 999, True]:
            exchange, ident = self.exchange()
            if replacement is None: del exchange['request']['gather_started_ms']
            else: exchange['request']['gather_started_ms'] = replacement
            exchange['response']['request_sha256'] = self.oracle.digest(exchange['request'])
            with self.subTest(clock=replacement), self.assertRaises(self.oracle.Rejected): self.inventory(exchange, ident)

    def test_late_publication_and_extended_deadline_rejected(self):
        for key, value in [('publication_checked_ms', 116000), ('deadline_ms', 116001)]:
            exchange, ident = self.exchange(); exchange['response']['timing'][key] = value
            with self.subTest(key=key), self.assertRaises(self.oracle.Rejected): self.inventory(exchange, ident)

    def test_duplicate_and_incomplete_backend_inventory_rejected(self):
        for mutation in ['duplicate', 'missing']:
            exchange, ident = self.exchange(); exchange['response']['aggregate_count'] = 2
            if mutation == 'duplicate': exchange['response']['pages'][0]['rows'] *= 2
            with self.subTest(mutation=mutation), self.assertRaises(self.oracle.Rejected): self.inventory(exchange, ident)

    def ttid(self):
        return ({'type': 'vital', 'vital_type': 'app_launch', 'metric': 'ttid', 'name': 'time_to_initial_display',
                 'application_id': 'app', 'session_id': 'session', 'view_id': 'launch', 'run_id': 'run',
                 'startup_type': 'cold_start', 'is_prewarmed': False, 'duration': 120_000_000_000, 'event_id': 'event'},
                {'session_id': 'session', 'views': {'ApplicationLaunch': 'launch'}, 'identity': {'run_id': 'run'},
                 'startup_control': {'ttid_event_id': 'event'}},
                {'application_id': 'app', 'app_launch_vitals': {'ttid': 1, 'ttfd': 0, 'fbc': 0, 'startup_type': 'cold_start', 'is_prewarmed': False}})

    def test_incidental_ttid_duration_does_not_block_ownership(self):
        event, local, expected = self.ttid(); self.oracle.validate_ttid(event, local, expected)
        with self.assertRaises(self.original.Rejected): self.original.validate_ttid(event, local, expected)

    def test_ttid_wrong_owner_or_malformed_duration_still_rejected(self):
        for key, value in [('view_id', 'foreign'), ('duration', -1), ('duration', True), ('duration', 1.5)]:
            event, local, expected = self.ttid(); event[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(self.oracle.Rejected): self.oracle.validate_ttid(event, local, expected)

    def test_scoped_cell_checks_both_workspace_boundaries_and_binds_oracle(self):
        raw = (self.origin/'host/cell.py').read_bytes()
        result = variant.render('cell.py', raw, self.contract['original_inputs']['host/cell.py'], semantic=True).decode()
        self.assertEqual(result.count('stage.verify_workspace(args.runtime_root)'), 2)
        self.assertNotIn('safety.protected(root)', result)
        self.assertIn("spec_from_file_location('oracle',args.runtime_root/'generated/scoped_oracle.py')", result)
        self.assertIn("summary['scoped_oracle_sha256']", result)

    def definition(self):
        authority = json.loads(scope.TRANSITION.read_text())['main_integration']
        return {'schema_version': 1, 'kind': 'S2_RESOURCE_FOLD_SEMANTICS', 'gates': ['S2:T03', 'S2:T08'], 'native_admitted': False,
                'source_revisions': self.contract['source_revisions'], 'original_root': str(self.origin),
                'diagnostic_rules': scope.DIAGNOSTICS, 'finite_scope': {'cells': self.contract['cells'], 'additional_builds': 0,
                    'retries': 0, 'native_execution_this_preparation': 0, 'backend_requests_this_preparation': 0},
                'original_source_contract': runtime.ref(self.origin/'source-contract.json'),
                'documentation_transition': runtime.ref(scope.TRANSITION),
                'original_document_manifest': runtime.ref(Path(authority['evidence_root'])/'original-input-manifest.json')}

    def test_authorized_document_transition_covers_exact_old_inputs(self):
        original = scope.validate(self.definition(), self.contract)
        self.assertEqual(len(original['side_documents']), 8)
        self.assertEqual(set(scope.protected()), set(scope.USER_PATHS))

    def test_scope_cannot_admit_native_or_add_a_cell(self):
        for mutation in ['native', 'cell', 'diagnostic']:
            value = copy.deepcopy(self.definition())
            if mutation == 'native': value['native_admitted'] = True
            elif mutation == 'cell': value['finite_scope']['cells'].append('extra')
            else: value['diagnostic_rules'].append('ownership')
            with self.subTest(mutation=mutation), self.assertRaises(Rejected): scope.validate(value, self.contract)

    def test_changed_scope_asset_rejected(self):
        value = self.definition(); value['original_source_contract']['sha256'] = '0'*64
        with self.assertRaises(Rejected): scope.validate(value, self.contract)

    def test_unapproved_historical_protected_path_rejected(self):
        value = self.definition(); actual = scope.shared.read
        def changed(path):
            result = actual(path)
            if str(path) == value['original_source_contract']['path']:
                result['side_documents']['foreign/path'] = '0'*64
            return result
        with patch.object(scope.shared, 'read', side_effect=changed), self.assertRaises(Rejected): scope.validate(value, self.contract)


if __name__ == '__main__': unittest.main()

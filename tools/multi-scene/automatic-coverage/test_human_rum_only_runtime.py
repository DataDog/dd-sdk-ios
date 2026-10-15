"""Consequential continuation boundaries, without device actions."""
import copy
import json
import os
from pathlib import Path
import shutil
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

import human_rum_only_runtime as runtime

ACTUAL_ROOT = Path(os.environ['MULTISCENE_CAPTURED_READER_ROOT']) if os.environ.get('MULTISCENE_CAPTURED_READER_ROOT') else None
PHASE = 'initial.root.toggle.effect'


class RuntimeBoundaries(unittest.TestCase):
    def test_scope_restores_after_interruption(self):
        ready, scenario = runtime.ready.native_ready, runtime.ready.scenario
        with self.assertRaises(InterruptedError):
            with runtime.runtime_mode():
                self.assertIs(runtime.ready.scenario, runtime.scenario)
                raise InterruptedError('owned process interrupted')
        self.assertIs(runtime.ready.native_ready, ready)
        self.assertIs(runtime.ready.scenario, scenario)

    def test_readiness_fault_is_diagnostic_but_idle_stays_required(self):
        with tempfile.TemporaryDirectory() as out:
            folder = Path(out).resolve()
            collector = SimpleNamespace(run='run', deadline=100, pid=1, binding={},
                rum_only=True, rum_only_diagnostics=[], evidence=[{'kind': 'launch', 'payload': {'layout': 'split', 'bundle': 'fixture'}}],
                snapshot=lambda *args: ({}, folder), live=lambda *args: None,
                cleanup_idle=lambda *args: {'state': 'NATIVE_INPUT_IDLE', 'run_id': 'run'})
            oracle = SimpleNamespace(one=lambda rows, label: rows[0])
            runner = SimpleNamespace(capture=SimpleNamespace(oracle=oracle),
                journey=SimpleNamespace(ready_controls=lambda *args: (_ for _ in ()).throw(ValueError('missing AX control'))))
            runtime.native_ready(collector, 'ready', runner, 'split')
            self.assertEqual(collector.rum_only_diagnostics[0]['check'], 'readiness.controls')
            self.assertEqual(json.loads((folder/'input-idle/proof.json').read_text())['state'], 'NATIVE_INPUT_IDLE')

    def test_idle_failure_is_fatal_even_when_controls_are_diagnostic(self):
        with tempfile.TemporaryDirectory() as out:
            collector = SimpleNamespace(run='run', deadline=100, pid=1, binding={},
                rum_only=True, rum_only_diagnostics=[], evidence=[{'kind': 'launch', 'payload': {'layout': 'split', 'bundle': 'fixture'}}],
                snapshot=lambda *args: ({}, Path(out).resolve()), live=lambda *args: None,
                cleanup_idle=lambda *args: {'state': 'TOUCHES_ACTIVE', 'run_id': 'run'})
            runner = SimpleNamespace(capture=SimpleNamespace(oracle=SimpleNamespace(one=lambda rows, label: rows[0])),
                journey=SimpleNamespace(ready_controls=lambda *args: {}))
            with self.assertRaisesRegex(ValueError, 'input not idle'):
                runtime.native_ready(collector, 'ready', runner, 'split')

    def test_early_input_is_fatal(self):
        collector = SimpleNamespace(rum_only=True, evidence=[{'kind': 'native_input'}], deadline=100,
                                    snapshot=lambda *args: ({}, Path('/unused')))
        with self.assertRaisesRegex(ValueError, 'input preceded readiness'):
            runtime.native_ready(collector, 'ready', None, 'split')


    def final_runner(self):
        return SimpleNamespace(final_cell=lambda root, key, supervisor_error=None:
            {'state': 'INVALID' if supervisor_error else 'PASS', 'reason': supervisor_error})

    def test_missing_final_grade_invalidates_overall(self):
        with tempfile.TemporaryDirectory() as out:
            result, code = runtime.final_result(self.final_runner(), Path(out).resolve(), 'cell', 0)
        self.assertEqual((result['state'], code), ('INVALID', 1))

    def test_failed_worker_invalidates_overall_without_regrading(self):
        result, code = runtime.final_result(self.final_runner(), Path('/unused'), 'cell', 1)
        self.assertEqual((result['state'], code), ('INVALID', 1))

    def test_final_failed_grade_invalidates_overall(self):
        with tempfile.TemporaryDirectory() as out:
            root = Path(out).resolve(); folder = root/'cells/cell'; folder.mkdir(parents=True)
            (folder/'rum-only-final-result.json').write_text('{"rum_verdict": "FAIL"}')
            result, code = runtime.final_result(self.final_runner(), root, 'cell', 0,
                grade_reference=runtime.s.reference(folder/'rum-only-final-result.json'))
        self.assertEqual((result['state'], code), ('INVALID', 1))


    def test_no_terminal_inventory_cannot_pass(self):
        run = dict(run_id='run', build='baseline-27.1', device='duo', framework='SwiftUI', layout='split')
        graded = runtime.rum_only.verdict(run, [{'kind': 'rum'}], [])
        self.assertEqual(graded['rum_verdict'], 'INCOMPLETE')


class CapturedFailureReplay(unittest.TestCase):
    """Local saved bytes only; these tests grant no native scenario credit."""
    @classmethod
    def setUpClass(cls):
        if ACTUAL_ROOT is None:
            raise unittest.SkipTest('saved native capture supplied only for local replay qualification')
        cls.runner, cls.plan = runtime.reader.verify(ACTUAL_ROOT)
        cls.cell = ACTUAL_ROOT/'runtime/cells/baseline-27.1-duo-SwiftUI-split-single'
        cls.result = json.loads((cls.cell/'cell-result.json').read_text())
        cls.run_id = cls.result['identity']['run_id']
        cls.rows = [json.loads(line) for line in (cls.cell/'input'/PHASE/'events.jsonl').read_text().splitlines()]
        cls.binding = next(r['payload'] for r in cls.rows if r['kind'] == 'human_window_binding')

    def collector(self, output):
        folder = Path(output)/PHASE
        shutil.copytree(self.cell/'input'/PHASE, folder)
        return SimpleNamespace(output=Path(output), run=self.run_id, binding=self.binding,
                               evidence=[], rum_only_diagnostics=[])

    def test_actual_extra_fields_are_preserved_as_diagnostic(self):
        with tempfile.TemporaryDirectory() as out:
            collector = self.collector(out)
            result, folder = runtime.rum_only.recover(collector, self.runner, PHASE, ValueError('incomplete AX'))
            view = result['payload']['topology']['accessibility'][0]['current_view']
            self.assertEqual(view['window'], self.binding['window'])
            self.assertEqual(view['reciprocal_memberships'], 1)
            self.assertIn('parent_children', view)
            self.assertEqual(collector.evidence, self.rows)
            self.assertEqual((folder/'events.jsonl').read_bytes(), (self.cell/'input'/PHASE/'events.jsonl').read_bytes())
            self.assertEqual(collector.rum_only_diagnostics[0]['check'], 'snapshot')

    def test_foreign_window_remains_fatal(self):
        rows = copy.deepcopy(self.rows)
        taken = next(r for r in reversed(rows) if r['kind'] == 'human_snapshot')
        taken['payload']['topology']['bound_window'] = 'foreign-window'
        with tempfile.TemporaryDirectory() as out:
            collector = self.collector(out)
            # Valid-envelope adversarial projection exercises the independent
            # owner check; original captured bytes are not modified.
            with patch.object(self.runner.capture.oracle, 'checkpoint', return_value=rows):
                with self.assertRaises(runtime.rum_only.EvidenceError):
                    runtime.rum_only.recover(collector, self.runner, PHASE, ValueError('incomplete AX'))
            self.assertEqual(collector.rum_only_diagnostics, [])

    def test_corrupt_writer_prefix_remains_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            collector = self.collector(out)
            (Path(out).resolve()/PHASE/'events.jsonl').write_bytes(b'{"broken": true}\n')
            with self.assertRaises(runtime.rum_only.EvidenceError):
                runtime.rum_only.recover(collector, self.runner, PHASE, ValueError('incomplete AX'))
            self.assertEqual(collector.rum_only_diagnostics, [])


class TerminalReplay(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ACTUAL_ROOT is None: raise unittest.SkipTest('accepted terminal capture supplied only for local qualification')
        cls.runner, plan = runtime.reader.verify(ACTUAL_ROOT)
        owner = runtime.ready.bound_read(plan['completed'][-1]['result'])
        selected = owner['selected']; root = Path(owner['plan']['path']).parent
        cell = root/'cells'/cls.runner.cell_key(selected)
        result = json.loads((cell/'cell-result.json').read_text())
        cls.run_context = dict(run_id=result['identity']['run_id'], **selected)
        cls.raw = (cell/'events.jsonl').read_bytes()
        cls.prefix = (cell/'input/background.before/background-events.jsonl').read_bytes()
        cls.receipts = json.loads((cell/'receipts.json').read_text())

    def test_accepted_terminal_bytes_validate_offline(self):
        rows = runtime.validate_terminal(self.runner, self.raw, self.prefix, self.run_context, self.receipts)
        self.assertTrue(rows)

    def test_foreign_final_run_is_fatal_even_with_complete_rum(self):
        foreign = dict(self.run_context, run_id='foreign')
        with self.assertRaisesRegex(runtime.rum_only.Rejected, 'foreign or incomplete local collection'):
            runtime.validate_terminal(self.runner, self.raw, self.prefix, foreign, self.receipts)

    def test_foreign_final_receipts_are_fatal(self):
        receipts = copy.deepcopy(self.receipts); receipts[-1]['run_id'] = 'foreign'
        with self.assertRaisesRegex(ValueError, 'foreign or missing final receipts'):
            runtime.validate_terminal(self.runner, self.raw, self.prefix, self.run_context, receipts)

    def test_changed_terminal_prefix_is_fatal(self):
        with self.assertRaisesRegex(runtime.rum_only.Rejected, 'committed Home prefix'):
            runtime.validate_terminal(self.runner, self.raw, b'changed', self.run_context, self.receipts)


class PublicationBoundaries(unittest.TestCase):
    def test_inputs_changed_during_publication_are_sticky_invalid(self):
        with tempfile.TemporaryDirectory() as out:
            root=Path(out).resolve(); folder=root/'cells/cell'; folder.mkdir(parents=True)
            member=folder/'events.jsonl'; member.write_text('original')
            grade=dict(rum_verdict='PASS',inputs={'events':runtime.s.reference(member)})
            (folder/'rum-only-final-result.json').write_text(json.dumps(grade))
            def publish(root, key, supervisor_error=None):
                if supervisor_error is None: member.write_text('replaced')
                return {'state':'INVALID' if supervisor_error else 'PASS'}
            runner=SimpleNamespace(final_cell=publish)
            with patch.object(runtime,'grade_final',return_value=grade):
                result,code=runtime.final_result(runner,root,'cell',0,grade_reference=runtime.s.reference(folder/'rum-only-final-result.json'))
            self.assertEqual((result['state'],code),('INVALID',1))



class ExecutorAnchorBoundaries(unittest.TestCase):
    def prepared(self, folder):
        runtime.s.save(folder/'receipts.json',[])
        runtime.s.save(folder/'rum-only-diagnostics.json',[])
        return dict(run_id='run',stage_id='stage',runtime_plan_sha256='plan')

    def inputs(self, folder):
        return dict(validated=runtime.s.reference(folder/'executor-terminal-validated.jsonl'),
            receipts=runtime.s.reference(folder/'receipts.json'),
            diagnostics=runtime.s.reference(folder/'rum-only-diagnostics.json'))

    def test_actual_validated_bytes_remain_immutable(self):
        with tempfile.TemporaryDirectory() as out:
            folder=Path(out).resolve(); stage=self.prepared(folder); raw=b'actual\n'
            runtime.publish_terminal_anchor(folder,stage,raw,raw)
            runtime.require_terminal_anchor(folder,stage,raw,raw,self.inputs(folder))
            with self.assertRaisesRegex(ValueError,'already consumed'):
                runtime.publish_terminal_anchor(folder,stage,raw,raw)

    def test_coherent_append_to_both_files_cannot_replace_validated_argument(self):
        with tempfile.TemporaryDirectory() as out:
            folder=Path(out).resolve(); stage=self.prepared(folder); raw=b'actual\n'
            runtime.publish_terminal_anchor(folder,stage,raw,raw)
            changed=raw+b'coherent-extra-row\n'
            (folder/'events.jsonl').write_bytes(changed)
            (folder/'native-preserved').mkdir(); (folder/'native-preserved/events.jsonl').write_bytes(changed)
            with self.assertRaisesRegex(ValueError,'actual executor validation'):
                runtime.require_terminal_anchor(folder,stage,changed,raw,self.inputs(folder))

    def test_anchor_replacement_before_first_freeze_is_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            root=Path(out).resolve(); folder=root/'cells/cell'; folder.mkdir(parents=True)
            stage=self.prepared(folder); original=runtime.publish_terminal_anchor(folder,stage,b'actual\n',b'actual\n')
            path=folder/'executor-terminal-anchor.json'; anchor=json.loads(path.read_text())
            anchor['coherent_replacement']=True; path.write_text(json.dumps(anchor))
            with self.assertRaisesRegex(ValueError,'bound binary/source changed'):
                runtime.grade_final(None,root,'cell',anchor_reference=original)

    def test_worker_grade_replacement_before_parent_read_is_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            root=Path(out).resolve(); folder=root/'cells/cell'; folder.mkdir(parents=True)
            path=folder/'rum-only-final-result.json'; path.write_text('{"rum_verdict":"PASS"}')
            receipt=runtime.s.reference(path); path.write_text('{"rum_verdict":"PASS","replaced":true}')
            runner=SimpleNamespace(final_cell=lambda root,key,supervisor_error=None:
                {'state':'INVALID' if supervisor_error else 'PASS'})
            result,code=runtime.final_result(runner,root,'cell',0,grade_reference=receipt)
            self.assertEqual((result['state'],code),('INVALID',1))

    def test_replacement_inside_anchor_publication_is_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            folder=Path(out).resolve(); stage=self.prepared(folder); save=runtime.s.save
            def replace(path,value):
                save(path,value)
                if Path(path).name == 'executor-terminal-anchor.json':
                    changed=dict(value,replaced=True); Path(path).write_text(json.dumps(changed))
            with patch.object(runtime.s,'save',side_effect=replace):
                with self.assertRaisesRegex(ValueError,'bound binary/source changed'):
                    runtime.publish_terminal_anchor(folder,stage,b'actual\n',b'actual\n')

    def test_original_consumed_admission_and_review_cannot_be_replaced(self):
        with tempfile.TemporaryDirectory() as out:
            folder=Path(out).resolve(); stage=self.prepared(folder)
            admission=folder/'admission.json'; review=folder/'review.json'
            admission.write_text('{"tool_owner":"original"}'); review.write_text('{"reviewer":"original"}')
            consumed={'admission':runtime.s.reference(admission),'review':runtime.s.reference(review)}
            runtime.publish_terminal_anchor(folder,stage,b'actual\n',b'actual\n',consumed_context=consumed)
            admission.write_text('{"tool_owner":"replacement"}'); review.write_text('{"reviewer":"replacement"}')
            inputs=dict(self.inputs(folder),admission=runtime.s.reference(admission),review=runtime.s.reference(review))
            with self.assertRaisesRegex(ValueError,'consumed admission or review replaced'):
                runtime.require_terminal_anchor(folder,stage,b'actual\n',b'actual\n',inputs)

    def test_missing_executor_anchor_is_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            with self.assertRaisesRegex(ValueError,'missing or redirected'):
                runtime.require_terminal_anchor(Path(out).resolve(),{},b'',b'',{})

    def test_helper_mutation_before_final_freeze_is_fatal(self):
        with tempfile.TemporaryDirectory() as out:
            root=Path(out).resolve(); paths=runtime.final_paths(root,'cell')
            for path in paths.values(): path.parent.mkdir(parents=True,exist_ok=True); path.write_text('{}')
            helper=root/'helper.py'; helper.write_text('original')
            (root/'runtime-plan.json').write_text(json.dumps({'helpers':{'fake':runtime.s.reference(helper)}}))
            helper.write_text('changed')
            with self.assertRaisesRegex(ValueError,'final helper identity changed'):
                runtime.grade_final(None,root,'cell',anchor_reference=runtime.s.reference(paths['anchor']))

    def test_helper_mutation_during_publication_is_sticky_invalid(self):
        with tempfile.TemporaryDirectory() as out:
            root=Path(out).resolve(); folder=root/'cells/cell'; folder.mkdir(parents=True)
            helper=root/'helper.py'; helper.write_text('original')
            grade=dict(rum_verdict='PASS',inputs={'helper:fake':runtime.s.reference(helper)})
            (folder/'rum-only-final-result.json').write_text(json.dumps(grade))
            def publish(root,key,supervisor_error=None):
                if supervisor_error is None: helper.write_text('changed')
                return {'state':'INVALID' if supervisor_error else 'PASS'}
            with patch.object(runtime,'grade_final',return_value=grade):
                result,code=runtime.final_result(SimpleNamespace(final_cell=publish),root,'cell',0,grade_reference=runtime.s.reference(folder/'rum-only-final-result.json'))
            self.assertEqual((result['state'],code),('INVALID',1))

    def test_anchor_observes_validator_argument_and_restores_on_interruption(self):
        with tempfile.TemporaryDirectory() as out:
            folder=Path(out).resolve(); stage=self.prepared(folder)
            validator=lambda raw,**kwargs: [{'actual':True}]
            module=SimpleNamespace(terminal_rows=validator)
            runner=SimpleNamespace(capture=SimpleNamespace(local_event_collection=module))
            with patch.object(runtime,'scenario',return_value=b'actual\n'):
                with self.assertRaises(InterruptedError):
                    with runtime.runtime_mode(runner,folder,stage):
                        runtime.ready.scenario(SimpleNamespace(receipts=[],rum_only_diagnostics=[]),runner,{},folder,None,None)
                        self.assertEqual(module.terminal_rows(b'actual\n',run_id='run',prefix=b'actual\n'),[{'actual':True}])
                        raise InterruptedError('stop')
            self.assertIs(module.terminal_rows,validator)
            self.assertEqual((folder/'executor-terminal-validated.jsonl').read_bytes(),b'actual\n')



class PlanBoundaries(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        value = os.environ.get('MULTISCENE_RUM_ONLY_ROOT')
        if not value:
            raise unittest.SkipTest('prepared source-bound plan supplied only for local qualification')
        cls.root = Path(value)
        cls.runner, cls.plan = runtime.verify(cls.root, reviewed=False)
        cls.original = runtime.ready.bound_read(cls.plan['reader_plan'])

    def modified_plan(self, changed):
        read = runtime.s.read
        plan_path = self.root/'runtime/runtime-plan.json'
        return patch.object(runtime.s, 'read', side_effect=lambda p: changed if Path(p) == plan_path else read(p))

    def test_source_identity_change_is_fatal(self):
        changed = copy.deepcopy(self.plan); changed['source'] = 'foreign-source'
        with self.modified_plan(changed), self.assertRaisesRegex(ValueError, 'original source/contract changed'):
            runtime.verify(self.root, reviewed=False)

    def test_helper_omission_is_fatal(self):
        changed = copy.deepcopy(self.plan); del changed['helpers'][runtime.ADAPTERS[0]]
        with self.modified_plan(changed), self.assertRaisesRegex(ValueError, 'helper closure changed'):
            runtime.verify(self.root, reviewed=False)

    def test_foreign_classification_is_fatal(self):
        read = runtime.ready.bound_read
        def changed(ref):
            value = read(ref)
            if ref == self.plan['stop_classification']:
                value = copy.deepcopy(value)
                value['bindings']['cell_result'] = {'path': '/foreign', 'sha256': 'foreign'}
            return value
        with patch.object(runtime.ready, 'bound_read', side_effect=changed), self.assertRaisesRegex(ValueError, 'another failed cell'):
            runtime.verify(self.root, reviewed=False)

    def test_fatal_evidence_cannot_be_reclassified_as_diagnostic(self):
        read = runtime.ready.bound_read
        def changed(ref):
            value = read(ref)
            if ref == self.plan['stop_classification']:
                value = copy.deepcopy(value)
                value['fatal_evidence_or_window_binding_failure_established'] = True
            return value
        with patch.object(runtime.ready, 'bound_read', side_effect=changed), self.assertRaisesRegex(ValueError, 'not qualified'):
            runtime.verify(self.root, reviewed=False)

    def test_missing_native_review_blocks_execution(self):
        with self.assertRaisesRegex(ValueError, 'missing or redirected session artifact'):
            runtime.verify(self.root)


if __name__ == '__main__': unittest.main()


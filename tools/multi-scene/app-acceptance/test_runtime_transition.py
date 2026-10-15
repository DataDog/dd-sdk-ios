"""Controls for changing host policy without changing qualified app products."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import capture_build
import journey_builds as builds
from acceptance_common import Rejected
from capture_contract import loads


ORIGINAL = '''def bind(root, arm=None):
    definition = read_definition(root)
    preparation = read_preparation(root)
    for path, digest in definition['helpers'].items():
        assert sha(path) == digest
    assert sha(__file__) == definition['adapter']
    assert source_identity(preparation)
    assert generated_inputs(preparation)
    assert protected_files(preparation)
    return make_guard(root, definition, preparation, arm)

def other_check(value):
    assert value == 'unchanged'
'''
SPLIT = '''def bind(root, arm=None):
    definition = read_definition(root)
    preparation = read_preparation(root)
    for path, digest in definition['helpers'].items():
        assert sha(path) == digest
    assert sha(__file__) == definition['adapter']
    return bind_sources(root, definition, preparation, arm)

def bind_sources(root, definition, preparation, arm=None):
    assert source_identity(preparation)
    assert generated_inputs(preparation)
    assert protected_files(preparation)
    return make_guard(root, definition, preparation, arm)

def other_check(value):
    assert value == 'unchanged'
'''


class RuntimeTransitionControls(unittest.TestCase):
    def setUp(self):
        self.original = {'/host/policy.py': 'old-policy', '/host/binder.py': 'old-binder',
                         '/app/recorder.swift': 'recorder', '/build/compiler.py': 'compiler'}
        self.current = dict(self.original, **{'/host/policy.py': 'new-policy', '/host/binder.py': 'new-binder'})
        self.allowed = {'/host/policy.py', '/host/binder.py'}
        self.changes = {p:dict(before=self.original[p],after=self.current[p]) for p in self.allowed}
        self.reviewed = dict(self.current)

    def check(self, changes=None, current=None, reviewed=None):
        return builds.runtime_helpers(self.original, self.current if current is None else current,
                                      self.changes if changes is None else changes,
                                      self.reviewed if reviewed is None else reviewed, self.allowed)

    def test_exact_host_transition_keeps_all_other_hashes(self):
        self.assertEqual(self.check(), self.changes)

    def test_missing_extra_traversal_and_unchanged_paths_rejected(self):
        for mode in ('missing', 'extra', 'traversal', 'unchanged'):
            rows=copy.deepcopy(self.changes)
            if mode=='missing': rows.pop('/host/policy.py')
            if mode=='extra': rows['/app/recorder.swift']=dict(before='recorder',after='edited')
            if mode=='traversal': rows['/host/../host/policy.py']=rows.pop('/host/policy.py')
            if mode=='unchanged': rows['/host/policy.py']['after']='old-policy'
            with self.subTest(mode=mode), self.assertRaises(Rejected): self.check(changes=rows)
        with self.assertRaisesRegex(ValueError,'duplicate JSON key'): loads(b'{"changes": {}, "changes": {}}')

    def test_old_new_review_and_non_transition_source_drift_rejected(self):
        for mode in ('old', 'new', 'review', 'compiler', 'app', 'missing-helper'):
            rows=copy.deepcopy(self.changes);current=dict(self.current);reviewed=dict(self.reviewed)
            if mode=='old': rows['/host/policy.py']['before']='foreign'
            if mode=='new': rows['/host/policy.py']['after']='foreign'
            if mode=='review': reviewed['/host/policy.py']='unreviewed'
            if mode=='compiler': current['/build/compiler.py']='changed'
            if mode=='app': current['/app/recorder.swift']='changed'
            if mode=='missing-helper': current.pop('/build/compiler.py')
            with self.subTest(mode=mode), self.assertRaises(Rejected): self.check(rows,current,reviewed)

    def test_source_binder_refactor_preserves_every_original_check(self):
        builds.binding_split(ORIGINAL,SPLIT)
        for changed in (SPLIT.replace('assert source_identity(preparation)','pass'),
                        SPLIT.replace('assert generated_inputs(preparation)','pass'),
                        SPLIT.replace('assert protected_files(preparation)','pass'),
                        SPLIT.replace("value == 'unchanged'",'True'),
                        SPLIT.replace('sha(path) == digest','True'),
                        SPLIT.replace('sha(__file__) == definition[\'adapter\']','True')):
            with self.subTest(changed=changed),self.assertRaises(Rejected): builds.binding_split(ORIGINAL,changed)

    def test_original_default_binder_still_rejects_changed_helpers(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);helper=root/'helper.py';helper.write_text('changed')
            (root/'definition.json').write_text(json.dumps(dict(qualified_helper_sha256={str(helper):'original'},adapter_sha256='old')))
            (root/'preparation.json').write_text('{}')
            with self.assertRaisesRegex(AssertionError,'Qualified helper changed'): capture_build.bind(root)

    def test_changed_or_substituted_transition_manifest_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);manifest=root/'transition.json';manifest.write_text('{}')
            for binding in ({'path':str(manifest),'sha256':'wrong'},
                            {'path':str(manifest),'sha256':builds.sha(manifest),'extra':True}):
                with self.assertRaises(Rejected): builds.transition_guard(root,root/'adapter.py',{},binding)
            link=root/'link.json';link.symlink_to(manifest)
            with self.assertRaises(Rejected): builds.transition_guard(root,root/'adapter.py',{},dict(path=str(link),sha256=builds.sha(link)))

    def test_review_controls_and_definition_identity_cannot_be_substituted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'definition.json').write_text('{}');(root/'completion.json').write_text('{}')
            controls=root/'controls.json';controls.write_text(json.dumps(dict(state='PASS_OFFLINE_ONLY',source_sha256={'x':'old'})))
            review=root/'review.json';review.write_text(json.dumps(dict(state='PASS',reviewer='/root/c06_runtime_plan',
                controls=dict(path=str(controls),sha256=builds.sha(controls)),source_sha256={'x':'current'})))
            manifest=root/'transition.json'
            value=dict(schema_version=1,state='REVIEWED_HOST_ONLY_REUSE',build_root=str(root),
                       definition_sha256=builds.sha(root/'definition.json'),completion_sha256=builds.sha(root/'completion.json'),
                       review=dict(path=str(review),sha256=builds.sha(review)))
            for mode in ('definition','review','controls-source'):
                changed=copy.deepcopy(value)
                if mode=='definition': changed['definition_sha256']='foreign'
                if mode=='review': changed['review']['sha256']='foreign'
                manifest.write_text(json.dumps(changed))
                with self.subTest(mode=mode),self.assertRaises(Rejected):
                    builds.transition_guard(root,root/'adapter.py',{},dict(path=str(manifest),sha256=builds.sha(manifest)))

    def test_product_drift_is_rejected_before_identity_can_be_reused(self):
        with tempfile.TemporaryDirectory() as tmp:
            app=Path(tmp);(app/'binary').write_bytes(b'changed')
            manifest=dict(files={'binary':{'sha256':hashlib.sha256(b'original').hexdigest()}},symlinks={})
            with self.assertRaisesRegex(Rejected,'complete installed product changed'): builds.product(app,manifest)

    def test_session_preflight_forwards_the_plan_transition_without_native_work(self):
        import journey_session as session
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);binding=dict(path='/reviewed/transition.json',sha256='frozen')
            plan=dict(build_root='/build',completion_sha256='completion',runtime_transition=binding,
                      definition={'limits':dict(native_seconds_per_arm=2400,backend_seconds_per_arm=600,cleanup_seconds=300)})
            with patch.object(session.workflow,'verify',return_value=plan), \
                 patch.object(session.workflow,'validate_native_admission',return_value={}), \
                 patch.object(session.workflow.builds,'verify') as verify, \
                 patch.object(session.operator,'publish'), \
                 patch.object(session.supervisor,'supervise',return_value=1), \
                 patch.object(session,'qualify',return_value=False):
                session.run(SimpleNamespace(root=root,arm='baseline',device='not-used'))
                verify.assert_called_once_with('/build','baseline','completion',runtime_transition=binding)

    def test_saved_baseline_addition_requires_its_own_reviewed_scope_and_hash(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp).resolve();here=root/'app-acceptance';here.mkdir();(root/'acceptance').mkdir()
            allowed={str(here/name) for name in builds.PAGINATION_TRANSITION_FILES}
            allowed.add(str(root/'acceptance/app_journey_transport.py'))
            additions={str(here/name) for name in builds.SAVED_BASELINE_ADDITIONS}
            for path in allowed|additions:Path(path).write_text('pass\n')
            original={name:'old-'+Path(name).name for name in allowed}
            current={name:builds.sha(name) for name in allowed|additions}
            changes={name:dict(before=original[name],after=current[name]) for name in allowed}
            definition={'qualified_helper_sha256':original}
            for name in ['definition.json','completion.json','preparation.json']:(root/name).write_text('{}')
            binder=root/'adapter.py';binder.write_text('pass\n');(here/'capture_build.py').write_text('pass\n')
            controls=root/'controls.json';controls.write_text(json.dumps(dict(state='PASS_OFFLINE_ONLY',source_sha256=current)))
            review=root/'review.json';review.write_text(json.dumps(dict(state='PASS',reviewer='/root/c06_runtime_plan',
                controls=dict(path=str(controls),sha256=builds.sha(controls)),source_sha256=current,
                changes_sha256=hashlib.sha256(json.dumps(changes,sort_keys=True,separators=(',',':')).encode()).hexdigest())))
            value=dict(schema_version=1,state='REVIEWED_HOST_ONLY_REUSE',scope='signed-in-saved-baseline-v4',
                       build_root=str(root),definition_sha256=builds.sha(root/'definition.json'),completion_sha256=builds.sha(root/'completion.json'),
                       review=dict(path=str(review),sha256=builds.sha(review)),changes=changes,
                       additions={name:current[name] for name in additions})
            manifest=root/'transition.json'
            with patch.object(builds,'__file__',str(here/'journey_builds.py')), \
                 patch.object(capture_build,'__file__',str(here/'capture_build.py')), \
                 patch.object(capture_build,'bind_sources',return_value=('guard','preparation')) as bind:
                manifest.write_text(json.dumps(value))
                self.assertEqual(builds.transition_guard(root,binder,definition,dict(path=str(manifest),sha256=builds.sha(manifest))),('guard','preparation'))
                for mode in ['missing','changed','foreign-scope']:
                    changed=copy.deepcopy(value);key=str(here/'saved_baseline.py')
                    if mode=='missing':changed['additions'].pop(key)
                    if mode=='changed':changed['additions'][key]='foreign'
                    if mode=='foreign-scope':changed['scope']='signed-in-pagination-v3'
                    manifest.write_text(json.dumps(changed));bind.reset_mock()
                    with self.subTest(mode=mode),self.assertRaises(Rejected):
                        builds.transition_guard(root,binder,definition,dict(path=str(manifest),sha256=builds.sha(manifest)))
                    bind.assert_not_called()

    def test_transition_cannot_bypass_original_completion_or_build_receipts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);receipt=root/'baseline';receipt.mkdir();(receipt/'compiler.json').write_text('changed')
            value=dict(state='TWO_SOURCE_BOUND_CAPTURE_PRODUCTS_QUALIFIED',arms={'baseline':dict(source=builds.ARMS['baseline'],
                       finished_at='2026-09-25T00:00:00+00:00',deadline='2026-09-25T00:01:00+00:00',receipts={'compiler.json':'original'})})
            (root/'completion.json').write_text(json.dumps(value))
            for fingerprint in ('wrong',builds.sha(root/'completion.json')):
                with self.subTest(fingerprint=fingerprint),self.assertRaises(Rejected):
                    builds.verify(root,'baseline',fingerprint,runtime_transition={'path':'unused','sha256':'unused'})


if __name__ == '__main__': unittest.main()

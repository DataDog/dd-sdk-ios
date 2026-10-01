"""Source substitution controls; no native actions or historical file mutations."""
import copy
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import human_reader_continuation as c


class BindingControls(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.reader = c.refresh.READER
        self.other = 'tools/multi-scene/automatic-coverage/human_fold.py'
        self.old = {'helpers': {self.reader:'old-reader', self.other:'old-fold', c.ready.CONTRACT:'old-oracle'}}
        self.review = {'bindings': {'source_and_contract_hashes': {str(c.ready.REPO/self.reader):'new-reader'}}}
        self.hashes = {str(self.root/'helpers'/n):d for n,d in self.old['helpers'].items()}
        self.hashes.update({str(c.ready.REPO/self.reader):'new-reader', str(c.ready.REPO/self.other):'old-fold'})

    def check(self):
        with patch.object(c.s,'sha',side_effect=lambda p:self.hashes[str(p)]):
            c.original_helpers(self.old,self.root,self.review)

    def test_only_reviewed_reader_can_replace_immutable_snapshot(self): self.check()

    def test_changed_original_reader_snapshot_rejects(self):
        self.hashes[str(self.root/'helpers'/self.reader)]='new-reader'
        with self.assertRaisesRegex(ValueError,'snapshot changed'): self.check()

    def test_changed_semantic_oracle_snapshot_rejects(self):
        self.hashes[str(self.root/'helpers'/c.ready.CONTRACT)]='changed'
        with self.assertRaisesRegex(ValueError,'snapshot changed'): self.check()

    def test_unreviewed_current_reader_rejects(self):
        self.hashes[str(c.ready.REPO/self.reader)]='unreviewed'
        with self.assertRaisesRegex(ValueError,'reviewed replacement'): self.check()

    def test_unrelated_helper_drift_has_no_exception(self):
        self.hashes[str(c.ready.REPO/self.other)]='changed'
        with self.assertRaisesRegex(ValueError,'nonreader helper changed'): self.check()

    def test_bound_source_cannot_be_redirected_or_replaced(self):
        f=self.root/'source';f.write_text('original');ref=c.s.reference(f)
        self.assertEqual(c.binary(ref),f)
        f.write_text('changed')
        with self.assertRaises(ValueError):c.binary(ref)
        f.unlink(); target=self.root/'target';target.write_text('original');f.symlink_to(target)
        with self.assertRaises(ValueError):c.binary(ref)

    def test_completed_or_foreign_cell_is_rejected_before_source_loading(self):
        for selected in c.ready.continuation.UNIVERSE[:4]+[dict(c.ready.continuation.UNIVERSE[4],device='regular')]:
            with self.subTest(selected=selected),patch.object(c,'component') as component:
                with self.assertRaisesRegex(ValueError,'only two remaining'):c.source(None,None,None,selected)
                component.assert_not_called()

    def test_component_review_rejects_native_credit_and_contract_drift(self):
        bindings={str(c.ready.REPO/n):'hash' for n in c.READER_PATHS}
        value=dict(state='PASS',findings=[],native_admitted=False,human_invitation=False,
                   bindings={'source_and_contract_hashes':bindings})
        for field in ('state','findings','native_admitted','human_invitation','hash'):
            bad=copy.deepcopy(value)
            if field=='state':bad[field]='BLOCKED'
            elif field=='findings':bad[field]=['unresolved']
            elif field!='hash':bad[field]=True
            with self.subTest(field=field),patch.object(c.ready,'bound_read',return_value=bad),patch.object(c.s,'sha',return_value='changed' if field=='hash' else 'hash'):
                with self.assertRaises(ValueError):c.component({})

    def test_historical_binding_requires_exact_original_and_copied_bytes(self):
        f=self.root/'historical';f.write_text('original');copied=c.s.reference(f)
        original=dict(copied,path=str(self.root/'changed-current'))
        (self.root/'changed-current').write_text('new reader')
        member=dict(original=original,copied=copied)
        self.assertEqual(c.ready.continuation.preserved_source(original,[member]),f)
        for mutation in ('original','copied','duplicate','bytes'):
            values=copy.deepcopy([member])
            if mutation=='original':values[0]['original']['sha256']='wrong'
            elif mutation=='copied':values[0]['copied']['sha256']='wrong'
            elif mutation=='duplicate':values.append(copy.deepcopy(member))
            else:f.write_text('replaced')
            with self.subTest(mutation=mutation),self.assertRaises(ValueError):
                c.ready.continuation.preserved_source(original,values)

    def test_no_implicit_historical_substitution(self):
        f=self.root/'current';f.write_text('new');ref=dict(path=str(f),sha256='old')
        with self.assertRaises(ValueError):c.ready.continuation.preserved_source(ref,[])


class VerifierInjection(unittest.TestCase):
    def test_admit_execute_and_supervisor_use_explicit_verifier_before_any_action(self):
        args=SimpleNamespace(root=Path('/unconsumed'))
        for function in (c.ready.admit,c.ready.execute,c.ready.run):
            verifier=Mock(side_effect=ValueError('new source invalid'))
            with self.subTest(function=function.__name__),patch.object(c.ready,'verify') as old:
                with self.assertRaisesRegex(ValueError,'new source invalid'):function(args,verifier=verifier)
                verifier.assert_called_once_with(args.root);old.assert_not_called()

    def test_default_verifier_remains_original(self):
        args=SimpleNamespace(root=Path('/unconsumed'))
        for function in (c.ready.admit,c.ready.execute,c.ready.run):
            with self.subTest(function=function.__name__),patch.object(c.ready,'verify',side_effect=ValueError('original source invalid')) as old:
                with self.assertRaisesRegex(ValueError,'original source invalid'):function(args)
                old.assert_called_once_with(args.root)


class PrefixComparison(unittest.TestCase):
    def setUp(self):
        self.reference={'path':'original stopped','sha256':'stopped-hash'}
        self.product=dict(path='original.app',bundle='original.bundle',product={'binary':'original'})
        self.old=dict(original_build_root='original-build',contract={'strict':'original'},
                      observer_refresh={'path':'original refresh'},
                      products={'baseline-26.5-SwiftUI-single':self.product},helpers={'reader':'old-reader'})
        self.helpers={'reader':{'path':'original reader','sha256':'old-reader'}}
        self.plan=dict(selected={'build':'baseline-26.5'},stopped=self.reference,
                       original_build_root=self.old['original_build_root'],contract=self.old['contract'],
                       effect_observation=c.ready.human_effect_recapture.CONTRACT,
                       product=self.product,source='original-source',helpers=self.helpers)
        self.enterContext(patch.object(c.ready,'bound_read',return_value={'arms':{'baseline-26.5':{'revision':'original-source'}}}))
        self.enterContext(patch.object(c.ready,'helper_binding',return_value=self.helpers))
        self.inventory=self.enterContext(patch.object(c.refresh.s,'product',return_value=self.product['product']))

    def test_exact_original_source_product_and_oracle_prefix_qualifies(self):
        c.compare_prefix([self.plan],self.old,self.reference)
        self.inventory.assert_called_once_with('original.app',bundle='original.bundle')

    def test_self_consistent_other_comparison_cannot_advance(self):
        for field in ('stopped','original_build_root','contract','effect_observation','product','source'):
            other=copy.deepcopy(self.plan);other[field]='different comparison'
            with self.subTest(field=field),self.assertRaisesRegex(ValueError,'another source comparison'):
                c.compare_prefix([other],self.old,self.reference)
        self.inventory.assert_not_called()

    def test_unrelated_original_helper_change_is_rejected(self):
        other=copy.deepcopy(self.plan);other['helpers']['reader']['sha256']='new-reader'
        with self.assertRaisesRegex(ValueError,'helper differs'):c.compare_prefix([other],self.old,self.reference)
        self.inventory.assert_not_called()

    def test_changed_original_native_product_is_rejected(self):
        self.inventory.return_value={'binary':'replaced'}
        with self.assertRaisesRegex(ValueError,'original product changed'):
            c.compare_prefix([self.plan],self.old,self.reference)


if __name__ == '__main__':unittest.main()

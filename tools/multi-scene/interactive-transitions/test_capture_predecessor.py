"""Source-bound reuse controls; no native commands or accepted UIKit rerun."""
import copy
import json
import plistlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import capture_qualification as q
import capture_predecessor as p
from capture_io import encoded
from acceptance_common import Rejected

SOURCE = '''def prepare(): pass
def verify(): pass
def helpers(): pass
def before_action():
    validate_live_capture()
def cell(root, framework):
    plan = reviewed(root)
    require(framework in plan['cells'])
    if framework == 'SwiftUI': require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS')
    run_native_cell()
def await_cell(root, framework):
    """Consume the real ready receipt."""
    plan = reviewed(root)
    require(framework in plan['cells'])
    if framework == 'SwiftUI': require(shared.read(root/'cells/UIKit/summary.json')['state'] == 'PASS')
    await_live_session()
'''


SHEET_OLD = """CONSTANT = 1
def select(request, raw, snapshot):
    verify_window()
    if is_pop():
        points = pop_points()
    else:
        candidates = old_candidates()
        sheet = old_surface(candidates)
        if t['framework'] == 'UIKit':
            verify_uikit(sheet)
        else:
            verify_swiftui(sheet)
    points = make_points(sheet)
    return command(points)
def publish():
    preserve_actual_return()
"""
SHEET_NEW = """def swiftui_sheet_surface(snapshot):
    return reviewed_native_surface(snapshot)
"""+SHEET_OLD.replace("        candidates = old_candidates()\n        sheet = old_surface(candidates)\n", "").replace(
    "        if t['framework'] == 'UIKit':\n", "        if t['framework'] == 'UIKit':\n            candidates = old_candidates()\n            sheet = old_surface(candidates)\n").replace(
    "            verify_swiftui(sheet)", "            sheet = swiftui_sheet_surface(snapshot)")


class Predecessor(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.prior=self.root/'prior';self.repo=self.root/'repo';self.build=self.root/'build'
        self.build.mkdir();self.prior.mkdir();self.repo.mkdir()
        self.write(self.build/'plan.json',{'compiled':'unchanged'})
        self.write(self.build/'A-simulator/build-result.json',{'product':'unchanged'})
        for name in p.FILES:self.write(self.prior/name,{})
        old=self.prior/'helpers'/p.QUALIFIER;old.parent.mkdir(parents=True);old.write_text(SOURCE)
        current=self.repo/p.QUALIFIER;current.parent.mkdir(parents=True);current.write_text(SOURCE.replace("root/'cells/UIKit/summary.json'", 'capture_predecessor.summary_path(root, plan)'))
        other=p.PREFIX+'native_contract.py';path=self.prior/'helpers'/other;path.write_text('native_oracle = True\n')
        old_helpers={p.QUALIFIER:p.shared.sha(old),other:p.shared.sha(path)}
        self.helpers=dict(old_helpers);self.helpers[p.QUALIFIER]=p.shared.sha(current)
        self.helpers[p.PREFIX+'capture_predecessor.py']='new-preparation-helper'
        self.device=dict(udid='device',runtime='runtime',deviceTypeIdentifier='iPad',name='test iPad',state='Shutdown')
        self.compiled={'arms':{'A-simulator':{'source':'sdk','fixture':'fixture'}}}
        self.products={'products':{'UIKit':{'bundle':'owned.uikit'}}}
        self.identity=dict(source='sdk',fixture='fixture',bundle='owned.uikit',framework='UIKit',tracking='automatic',run_id='run',pid=12)
        self.plan=dict(cells=['UIKit'],release_acceptance=False,gate_closures=[],device=self.device,helpers=old_helpers,
            build_root=str(self.build),build_plan=p.shared.sha(self.build/'plan.json'),build_receipt=p.shared.sha(self.build/'A-simulator/build-result.json'))
        self.write(self.prior/'plan.json',self.plan)
        self.write(self.prior/'cells/UIKit/summary.json',dict(state='PASS',scenario='PASS',evidence='PASS',cleanup='PASS',
            release_acceptance=False,gate_closures=[],restored_at=10,cleanup_deadline=20,identity=self.identity))
        self.write(self.prior/'cells/UIKit/native-summary.json',dict(identity=self.identity,transitions={
            n:dict(native={'state':'NATIVE_QUALIFIED'},ownership={'semantic_expectation':'FAIL' if n.endswith('finish') else 'PASS'})
            for n in ['pop.finish','pop.cancel','dismiss.finish','dismiss.cancel']}))
        self.write(self.prior/'fresh-worker-quiescence.json',dict(native_identity=self.identity,worker_stopped=True,
            runner_stopped=True,all_published_requests_complete=True,tool_pending=None,local_pending=None,uncertain_attempts=[],
            requests=[{'input_complete':True} for _ in range(11)],plan_sha256=p.shared.sha(self.prior/'plan.json')))
        self.write(self.prior/'cleanup-readback.json',{k:True for k in ['worker_quiescent','runner_stopped','app_and_data_absent',
            'original_pid_absent','non_task_inventory_unchanged','actual_session_absence']})
        self.write(self.prior/'controls.json',dict(state='PASS',plan_sha256=p.shared.sha(self.prior/'plan.json'),helpers=old_helpers))
        self.write(self.prior/'review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
            plan_sha256=p.shared.sha(self.prior/'plan.json'),controls_sha256=p.shared.sha(self.prior/'controls.json')))
        self.write(self.prior/'outcome-review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
            summary={'sha256':p.shared.sha(self.prior/'cells/UIKit/summary.json')},cleanup={'sha256':p.shared.sha(self.prior/'cleanup-readback.json')}))
        self.addCleanup(patch.stopall);patch.object(p.shared,'REPO',self.repo).start()
    def write(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(encoded(value))
    def bind(self,**changes):
        args=dict(root=self.prior,build_root=self.build,compiled=self.compiled,products=self.products,device=self.device,helpers=self.helpers)
        args.update(changes);return p.bind(**args)
    def changed(self,name,update):
        path=self.prior/name;old=path.read_bytes();value=json.loads(old);update(value);self.write(path,value)
        try:
            with self.assertRaises(Rejected):self.bind()
        finally:path.write_bytes(old)
    def test_restored_capture_pass_reuses_no_cell_and_preserves_semantic_failures(self):
        receipt=self.bind();self.assertFalse(receipt['release_acceptance'])
        self.assertEqual(set(receipt['files']),set(p.FILES))
        new=dict(self.plan,cells=['SwiftUI'],predecessor=receipt,helpers=self.helpers)
        p.verify(new,self.compiled,self.products)
        next_root=self.root/'next';next_root.mkdir()
        self.assertEqual(p.summary_path(next_root,new),(self.prior/'cells/UIKit/summary.json').resolve())
        self.assertFalse((next_root/'cells/UIKit').exists())
    def test_failed_late_or_release_predecessor_rejected(self):
        for field,value in [('state','INVALID'),('scenario','NOT_EXECUTED'),('evidence','INCOMPLETE'),('cleanup','INCOMPLETE'),
                            ('restored_at',21),('release_acceptance',True),('gate_closures',['H11'])]:
            with self.subTest(field=field):self.changed('cells/UIKit/summary.json',lambda r:r.update({field:value}))
    def test_foreign_build_source_fixture_bundle_and_device_rejected(self):
        for key in ['source','fixture','bundle','framework','tracking','run_id']:
            with self.subTest(key=key):self.changed('cells/UIKit/summary.json',lambda r:r['identity'].update({key:'foreign'}))
        for key in ['udid','runtime','deviceTypeIdentifier','state']:
            with self.subTest(key=key),self.assertRaises(Rejected):self.bind(device=dict(self.device,**{key:'foreign'}))
        self.changed('plan.json',lambda r:r.update(build_plan='old'))
        self.changed('plan.json',lambda r:r.update(build_receipt='old'))
    def test_pending_input_incomplete_inventory_and_cleanup_rejected(self):
        for key,value in [('worker_stopped',False),('runner_stopped',False),('all_published_requests_complete',False),
                          ('local_pending',42),('tool_pending','capture'),('uncertain_attempts',['input']),('requests',[])]:
            with self.subTest(key=key):self.changed('fresh-worker-quiescence.json',lambda r:r.update({key:value}))
        self.changed('fresh-worker-quiescence.json',lambda r:r['requests'][0].update(input_complete=False))
        self.changed('cleanup-readback.json',lambda r:r.update(app_and_data_absent=False))
        self.changed('cells/UIKit/native-summary.json',lambda r:r['transitions'].pop('pop.finish'))
    def test_missing_linked_and_changed_evidence_rejected(self):
        path=self.prior/'fresh-worker-return.json';old=path.read_bytes();path.unlink()
        with self.assertRaises(Rejected):self.bind()
        target=self.root/'outside.json';target.write_bytes(old);path.symlink_to(target)
        with self.assertRaises(Rejected):self.bind()
        path.unlink();path.write_bytes(old)
        receipt=self.bind();path.write_bytes(b'{"changed":true}')
        with self.assertRaises(Rejected):p.verify(dict(self.plan,cells=['SwiftUI'],predecessor=receipt,helpers=self.helpers),self.compiled,self.products)
    def test_unreviewed_or_altered_helpers_rejected(self):
        self.changed('outcome-review.json',lambda r:r.update(state='FAIL'))
        self.changed('review.json',lambda r:r.update(reviewer='other'))
        self.changed('controls.json',lambda r:r.update(plan_sha256='old'))
        changed=dict(self.helpers);changed[p.PREFIX+'native_contract.py']='changed'
        with self.assertRaises(Rejected):self.bind(helpers=changed)
        changed=dict(self.helpers);changed[p.PREFIX+'unreviewed.py']='extra'
        with self.assertRaises(Rejected):self.bind(helpers=changed)
    def test_changed_native_body_is_not_hidden_by_entry_guard_mapping(self):
        allowed=SOURCE.replace("root/'cells/UIKit/summary.json'", 'capture_predecessor.summary_path(root, plan)')
        self.assertIn('cell',p.runtime_mapping(SOURCE,allowed))
        for changed in [allowed.replace('run_native_cell()','run_other_cell()'),
                        allowed.replace('validate_live_capture()','skip_capture()'),allowed+'\ndef new_native_effect(): pass\n',
                        allowed.replace("require(framework in plan['cells'])", 'require(True)'),
                        allowed.replace("== 'PASS'", "!= 'PASS'"),
                        allowed.replace('capture_predecessor.summary_path(root, plan)', 'foreign_summary(root)')]:
            with self.subTest(source=changed),self.assertRaises(Rejected):p.runtime_mapping(SOURCE,changed)
    def test_sheet_delta_requires_public_inventory_and_binds_exact_source(self):
        old = self.prior/'helpers'/p.INPUT; old.write_text(SHEET_OLD)
        current = self.repo/p.INPUT; current.write_text(SHEET_NEW)
        old_hash = p.shared.sha(old); new_hash = p.shared.sha(current)
        self.plan['helpers'][p.INPUT] = old_hash; self.helpers[p.INPUT] = new_hash
        self.write(self.prior/'plan.json',self.plan)
        self.write(self.prior/'controls.json',dict(state='PASS',plan_sha256=p.shared.sha(self.prior/'plan.json'),helpers=self.plan['helpers']))
        self.write(self.prior/'review.json',dict(state='PASS',reviewer='/root/c06_runtime_plan',
            plan_sha256=p.shared.sha(self.prior/'plan.json'),controls_sha256=p.shared.sha(self.prior/'controls.json')))
        worker=p.shared.read(self.prior/'fresh-worker-quiescence.json');worker['plan_sha256']=p.shared.sha(self.prior/'plan.json')
        self.write(self.prior/'fresh-worker-quiescence.json',worker)
        with self.assertRaisesRegex(Rejected, 'requires reviewed public native inventory'):
            self.bind()

    def test_predecessor_cannot_enable_candidate_or_duplicate_uikit_execution(self):
        receipt=self.bind()
        for cells in [['UIKit'],['UIKit','SwiftUI'],['candidate'],[]]:
            with self.subTest(cells=cells),self.assertRaises(Rejected):p.verify(dict(self.plan,cells=cells,predecessor=receipt),self.compiled,self.products)
        with self.assertRaises(Rejected):p.verify(dict(self.plan,cells=['SwiftUI']),self.compiled,self.products)




class SourceMappings(unittest.TestCase):
    def test_oracle_mapping_preserves_entire_existing_module(self):
        old = "CONSTANT = 1\ndef target(before,identifier,binding):\n    value=before['payload']['topology']\n    item=value['item']\n    validate(item)\n    return item\n"
        call = "    accessibility_owner(value['accessibility'],item,binding['window'])\n"
        new = "def accessibility_owner(inventory,selected,window):\n    check_graph(inventory)\n"+old.replace('    validate(item)\n',call+'    validate(item)\n')
        p.source_mapping(old,new,'oracle')
        for changed in [new.replace('validate(item)','skip(item)'),new.replace('CONSTANT = 1','CONSTANT = 2'),
                        new.replace(call,''),new.replace(call,call+call),
                        new.replace(call,'').replace('    return item\n','    return item\n'+call),
                        new.replace(call,'').replace('    item=',call+'    item='),new+'\ndef extra_native(): pass\n']:
            with self.subTest(source=changed),self.assertRaises(Rejected):p.source_mapping(old,changed,'oracle')

    def test_sheet_mapping_preserves_uikit_and_every_shared_statement(self):
        proof = p.sheet_input_mapping(SHEET_OLD, SHEET_NEW)
        self.assertEqual(set(proof), {'unchanged_module', 'swiftui_helper'})
        for original, replacement in [('CONSTANT = 1', 'CONSTANT = 2'),
                ('verify_window()', 'skip_window()'), ('pop_points()', 'other_points()'),
                ('old_candidates()', 'weaker_candidates()'), ('verify_uikit(sheet)', 'skip_uikit(sheet)'),
                ('make_points(sheet)', 'change_gesture(sheet)'), ('command(points)', 'other_command(points)'),
                ('preserve_actual_return()', 'substitute_old_return()')]:
            with self.subTest(original=original), self.assertRaises(Rejected):
                p.sheet_input_mapping(SHEET_OLD, SHEET_NEW.replace(original, replacement))
        for source in [SHEET_NEW+"\ndef new_side_effect(): pass\n",
                       SHEET_NEW.replace("t['framework'] == 'UIKit'", "t['framework'] != 'UIKit'"),
                       SHEET_NEW.replace('    verify_window()', "    if t['framework'] == 'UIKit':\n        pass\n    else:\n        pass\n    verify_window()"),
                       SHEET_NEW.replace('def swiftui_sheet_surface(snapshot):', 'def other_helper(snapshot):')]:
            with self.subTest(source=source), self.assertRaises(Rejected):
                p.sheet_input_mapping(SHEET_OLD, source)

    def test_sheet_mapping_rejects_missing_original_selection_or_existing_helper(self):
        for old in [SHEET_OLD.replace('def select(', 'def different('), SHEET_NEW,
                    SHEET_OLD.replace("t['framework'] == 'UIKit'", "t['framework'] == 'SwiftUI'")]:
            with self.subTest(source=old), self.assertRaises(Rejected):
                p.sheet_input_mapping(old, SHEET_NEW)

    def test_builder_mapping_allows_only_preparation_function_change(self):
        old='SCOPE = 1\ndef prepare(): pass\ndef build(): check_product()\n'
        new=old.replace('def prepare(): pass','def prepare(flag=False): freeze(flag)')
        p.source_mapping(old,new,'builder')
        for changed in [new.replace('check_product()','skip_product()'),new.replace('SCOPE = 1','SCOPE = 2')]:
            with self.subTest(source=changed),self.assertRaises(Rejected):p.source_mapping(old,changed,'builder')


class BuildMappings(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name);self.oldroot=self.base/'old';self.newroot=self.base/'new';self.repo=self.base/'repo'
        self.addCleanup(patch.stopall);patch.object(p.shared,'REPO',self.repo).start()
        source=(Path(__file__).resolve().parents[1]/'automatic-coverage/HumanObservation.swift').read_bytes()
        self.old=self.make(self.oldroot,source,False)
        current=p.accessibility_capture.render_human(source,p.shared.sha(self.oldroot/'A-simulator/client/HumanObservation.swift'))
        self.new=self.make(self.newroot,current,True)
        self.oldproduct=p.shared.read(self.oldroot/'A-simulator/build-result.json')
        self.newproduct=p.shared.read(self.newroot/'A-simulator/build-result.json')
        self.prior=dict(build_root=str(self.oldroot),build_plan=p.shared.sha(self.oldroot/'plan.json'),
                        build_receipt=p.shared.sha(self.oldroot/'A-simulator/build-result.json'))

    def save(self,path,value):
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(encoded(value))

    def make(self,root,human,overlay):
        folder=root/'A-simulator';client=folder/'client';client.mkdir(parents=True);sdk=folder/'sdk';sdk.mkdir()
        (sdk/'SDK.swift').write_text('// identical SDK\n');(folder/'source.tar').write_bytes(b'identical SDK archive')
        for name in ['UIKitApp.swift','SwiftUIApp.swift','Observation.swift','TransitionObservation.swift']:(client/name).write_text('// '+name+'\n')
        (client/'HumanObservation.swift').write_bytes(human)
        fixture=p.build.digest({f.name:p.shared.sha(f) for f in client.glob('*.swift')})
        for name in ['UIKitTransitions.plist','SwiftUITransitions.plist']:(client/name).write_bytes(plistlib.dumps(dict(TransitionFixture=fixture,other='unchanged')))
        helper_source={p.BUILDER:'def prepare(): pass\ndef verify(): check_source()\n',p.PREFIX+'common.py':'scope = True\n'}
        if overlay:
            helper_source[p.BUILDER]=helper_source[p.BUILDER].replace('def prepare(): pass','def prepare(flag=False): freeze(flag)')
            helper_source[p.PREFIX+'accessibility_capture.py']=Path(p.accessibility_capture.__file__).read_text()
            helper_source[p.PREFIX+'test_accessibility_capture.py']='# bound controls\n'
        for name,text in helper_source.items():
            f=root/'helpers'/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text)
            f=self.repo/name;f.parent.mkdir(parents=True,exist_ok=True);f.write_text(text)
        bound=dict(source=p.shared.ARMS['A'],archive_sha256=p.shared.sha(folder/'source.tar'),sdk=p.shared.tree(sdk),
                   client=p.shared.tree(client),bundle_prefix='owned',fixture=fixture)
        plan=dict(arms={'A-simulator':bound},native_admitted=False,helpers=p.shared.tree(root/'helpers'),contract='same',
                  fixture_sources={'same':'source'},toolchain='same',observer='actual-pan-callbacks',observer_cost_partition=True)
        if overlay:plan['public_accessibility_inventory']=True
        self.save(root/'plan.json',plan);products={}
        for framework in ['UIKit','SwiftUI']:
            app=folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Transitions.app');app.mkdir(parents=True)
            (app/'Info.plist').write_bytes(plistlib.dumps(dict(TransitionSource=bound['source'],TransitionFixture=fixture,
                DTSDKName='iphonesimulator27.1',MinimumOSVersion='18.0')));(app/framework).write_text(framework+'-'+fixture)
            products[framework]=dict(path=str(app),bundle='owned.'+framework.lower(),product=self.product(app))
        receipt=dict(state='QUALIFIED_BUILD_ONLY',key='A-simulator',source=bound['source'],plan_sha256=p.shared.sha(root/'plan.json'),
                     finished_at=2,compiler={'membership':'frozen'},products=products)
        self.save(folder/'build-result.json',receipt)
        self.save(folder/'build-admission.json',dict(started_at=1,deadline=3,plan_sha256=p.shared.sha(root/'plan.json')))
        return plan

    @staticmethod
    def product(app,**unused):return {'files':p.shared.tree(app)}

    def actual(self,root):
        with patch.object(p.build,'compiled',return_value={'membership':'frozen'}),patch.object(p.shared,'product',side_effect=self.product):
            return p.verified_build(root)

    def mapping(self,products=None):
        def verified(root):return (self.old,self.oldproduct) if Path(root).resolve()==self.oldroot.resolve() else (self.new,self.newproduct)
        with patch.object(p,'verified_build',side_effect=verified):
            return p.mapped_build(self.prior,self.newroot,self.new,self.newproduct if products is None else products)

    def test_original_and_new_build_artifacts_are_independently_checked(self):
        self.actual(self.oldroot);self.actual(self.newroot)
        for relative in ['source.tar','sdk/SDK.swift','client/UIKitApp.swift','helpers-ignored']:
            if relative=='helpers-ignored':path=self.newroot/'helpers'/p.PREFIX/'common.py'
            else:path=self.newroot/'A-simulator'/relative
            raw=path.read_bytes();path.write_bytes(raw+b'changed')
            try:
                with self.subTest(path=relative),self.assertRaises(Rejected):self.actual(self.newroot)
            finally:path.write_bytes(raw)
        with patch.object(p.build,'compiled',return_value={'membership':'changed'}),self.assertRaises(Rejected):p.verified_build(self.oldroot)
        path=Path(self.oldproduct['products']['UIKit']['path'])/'UIKit';path.write_text('changed')
        with self.assertRaises(Rejected):self.actual(self.oldroot)

    def test_exact_overlay_maps_distinct_fixtures_products_and_unchanged_sdk(self):
        proof,old,products=self.mapping()
        self.assertEqual(old,self.old);self.assertEqual(products,self.oldproduct)
        self.assertNotEqual(proof['old_fixture'],proof['new_fixture'])
        self.assertNotEqual(proof['old_products_sha256'],proof['new_products_sha256'])
        self.assertFalse(proof['release_acceptance']);self.assertEqual(proof['gate_closures'],[])

    def test_sdk_archive_source_observer_and_helper_mutations_reject(self):
        changes=[lambda n:n['arms']['A-simulator']['sdk'].update(foreign='source'),
                 lambda n:n['arms']['A-simulator'].update(archive_sha256='other'),
                 lambda n:n['arms']['A-simulator'].update(source='candidate'),
                 lambda n:n['arms']['A-simulator'].update(fixture=self.old['arms']['A-simulator']['fixture']),
                 lambda n:n.update(observer='original-began'),lambda n:n.update(observer_cost_partition=False),
                 lambda n:n.update(public_accessibility_inventory=False),lambda n:n['fixture_sources'].update(other='source'),
                 lambda n:n['helpers'].update(extra='helper'),lambda n:n['helpers'].update({p.PREFIX+'common.py':'changed'})]
        for change in changes:
            saved=copy.deepcopy(self.new);change(self.new)
            try:
                with self.subTest(change=change),self.assertRaises(Rejected):self.mapping()
            finally:self.new=saved

    def test_copied_client_metadata_and_human_transformation_are_exact(self):
        for name in ['HumanObservation.swift','SwiftUITransitions.plist']:
            path=self.newroot/'A-simulator/client'/name;raw=path.read_bytes()
            if name.endswith('.plist'):
                value=plistlib.loads(raw);value['extra']='unreviewed';path.write_bytes(plistlib.dumps(value))
            else:path.write_bytes(raw+b'// unreviewed\n')
            try:
                with self.subTest(name=name),self.assertRaises(Rejected):self.mapping()
            finally:path.write_bytes(raw)
        self.new['arms']['A-simulator']['client']['SwiftUIApp.swift']='changed'
        with self.assertRaises(Rejected):self.mapping()

    def test_old_binding_and_new_product_cannot_be_substituted(self):
        with self.assertRaises(Rejected):self.mapping(products=self.oldproduct)
        self.prior['build_receipt']='foreign'
        with self.assertRaises(Rejected):self.mapping()

    def test_reviewed_live_helpers_are_required(self):
        path=self.repo/p.PREFIX/'accessibility_capture.py';path.write_text('changed')
        with self.assertRaises(Rejected):self.mapping()


if __name__=='__main__':unittest.main()

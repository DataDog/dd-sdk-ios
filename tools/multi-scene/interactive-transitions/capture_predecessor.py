"""Reuse one completed UIKit mechanism qualification before a SwiftUI-only cell."""
import ast
import plistlib
from pathlib import Path
import build
import accessibility_capture

shared = build.shared
require = build.require
PREFIX = 'tools/multi-scene/interactive-transitions/'
QUALIFIER = PREFIX + 'capture_qualification.py'
ORACLE = 'tools/multi-scene/automatic-coverage/human_contract.py'
BUILDER = PREFIX + 'build.py'
FILES = ['plan.json', 'review.json', 'controls.json', 'outcome-review.json',
         'cells/UIKit/summary.json', 'cells/UIKit/native-summary.json',
         'cells/UIKit/restore-shutdown.json', 'cells/UIKit/restore-shutdown.log',
         'cells/UIKit/interaction-end.json', 'fresh-worker-quiescence.json',
         'fresh-worker-return.json', 'cleanup-readback.json',
         'sessions/UIKit/creator-session-end-invocation.json']


def runtime_mapping(previous, current):
    """Only preparation/verification and the predecessor entry guard may change."""
    def functions(source):
        return {n.name: n for n in ast.parse(source).body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
    old, new = functions(previous), functions(current)
    require(set(old) == set(new), 'qualification runtime function inventory changed')
    kept = {}
    for name in old:
        if name in ['prepare', 'verify', 'helpers']:
            continue  # Their explicit diff is covered by the scoped reuse review.
        left, right = old[name], new[name]
        if name in ['await_cell', 'cell']:
            # Permit exactly the prior-summary lookup change, including functions
            # with docstrings; compare every guard and native statement unchanged.
            lookup = ast.parse("capture_predecessor.summary_path(root, plan)", mode='eval').body
            original = ast.parse("root/'cells/UIKit/summary.json'", mode='eval').body
            class Lookup(ast.NodeTransformer):
                count = 0
                def visit_Call(self, node):
                    if ast.dump(node) == ast.dump(lookup):
                        self.count += 1
                        return original
                    return self.generic_visit(node)
            replacement = Lookup()
            right = replacement.visit(right)
            require(replacement.count == 1, 'qualification predecessor lookup missing or duplicated: ' + name)
        a, b = ast.dump(left), ast.dump(right)
        require(a == b, 'qualification native behavior changed: ' + name)
        kept[name] = build.digest(a)
    return kept


def source_mapping(previous, current, kind):
    """Compare complete modules after removing only the reviewed optional delta."""
    old, new = ast.parse(previous), ast.parse(current)
    if kind == 'builder':
        for module in [old, new]:
            found = [n for n in module.body if isinstance(n, ast.FunctionDef) and n.name == 'prepare']
            require(len(found) == 1, 'ambiguous build preparation mapping')
            module.body.remove(found[0])
    elif kind == 'oracle':
        found = [n for n in new.body if isinstance(n, ast.FunctionDef) and n.name == 'accessibility_owner']
        require(len(found) == 1 and not any(isinstance(n, ast.FunctionDef) and n.name == 'accessibility_owner' for n in old.body),
                'ambiguous accessibility ownership mapping')
        new.body.remove(found[0])
        target = [n for n in new.body if isinstance(n, ast.FunctionDef) and n.name == 'target']
        require(len(target) == 1, 'ambiguous target mapping')
        call = ast.parse("accessibility_owner(value['accessibility'],item,binding['window'])").body[0]
        indices = [i for i,n in enumerate(target[0].body) if ast.dump(n) == ast.dump(call)]
        require(len(indices) == 1, 'ownership assertion missing or duplicated')
        selections = [i for i,n in enumerate(target[0].body) if isinstance(n,ast.Assign)
                      and len(n.targets) == 1 and isinstance(n.targets[0],ast.Name) and n.targets[0].id == 'item']
        require(len(selections) == 1 and indices[0] == selections[0]+1,
                'ownership assertion must immediately follow target selection')
        del target[0].body[indices[0]]
    else:
        require(False, 'unknown source mapping')
    require(ast.dump(old) == ast.dump(new), 'source changed beyond reviewed ' + kind + ' delta')
    return build.digest(ast.dump(old))


def verified_build(root):
    """Recheck a frozen build without requiring historical workspace metadata."""
    root = Path(root).resolve(strict=True); plan = shared.read(root/'plan.json')
    require(list(plan['arms']) == ['A-simulator'] and plan['native_admitted'] is False,
            'mapped build is not baseline-only preparation')
    require(shared.tree(root/'helpers') == plan['helpers'], 'mapped compiler helper tree changed')
    folder = root/'A-simulator'; bound = plan['arms']['A-simulator']
    require(shared.sha(folder/'source.tar') == bound['archive_sha256']
            and shared.tree(folder/'sdk') == bound['sdk'] and shared.tree(folder/'client') == bound['client'],
            'mapped source/archive/client changed')
    receipt = shared.read(folder/'build-result.json'); admission = shared.read(folder/'build-admission.json')
    require(receipt['state'] == 'QUALIFIED_BUILD_ONLY' and receipt['key'] == 'A-simulator'
            and receipt['source'] == bound['source']
            and receipt['plan_sha256'] == admission['plan_sha256'] == shared.sha(root/'plan.json')
            and admission['started_at'] < receipt['finished_at'] < admission['deadline'], 'mapped build receipt differs')
    require(receipt['compiler'] == build.compiled(folder, bound), 'mapped compiler membership/objects changed')
    require(set(receipt['products']) == {'UIKit','SwiftUI'}, 'mapped product inventory changed')
    for framework,value in receipt['products'].items():
        app = folder/'DerivedData/Build/Products/Release-iphonesimulator'/(framework+'Transitions.app')
        require(Path(value['path']).resolve(strict=True) == app.resolve(strict=True)
                and value['bundle'] == bound['bundle_prefix']+'.'+framework.lower()
                and shared.product(app,bundle=value['bundle']) == value['product'], 'mapped product changed')
        info = plistlib.loads((app/'Info.plist').read_bytes())
        require(info['TransitionSource'] == bound['source'] and info['TransitionFixture'] == bound['fixture']
                and info['DTSDKName'] == 'iphonesimulator27.1' and info['MinimumOSVersion'] == '18.0',
                'mapped built source/platform identity differs')
    return plan,receipt


def mapped_build(prior, build_root, compiled, products):
    old_root = Path(prior['build_root']).resolve(strict=True)
    require(old_root != build_root.resolve(strict=True)
            and prior['build_plan'] == shared.sha(old_root/'plan.json')
            and prior['build_receipt'] == shared.sha(old_root/'A-simulator/build-result.json'), 'original mapped build binding changed')
    old,old_product = verified_build(old_root); new,new_product = verified_build(build_root)
    require(new == compiled and all(products.get(k) == v for k,v in new_product.items()), 'new mapped product receipt substituted')
    require(old.get('public_accessibility_inventory',False) is False and new.get('public_accessibility_inventory') is True,
            'unreviewed accessibility overlay lineage')
    require(all(old[k] == new[k] for k in ['contract','fixture_sources','toolchain','observer','observer_cost_partition'])
            and new['observer'] == 'actual-pan-callbacks' and new['observer_cost_partition'] is True,
            'mapped source/compiler/observer contract changed')
    a,b = old['arms']['A-simulator'],new['arms']['A-simulator']
    require(a['source'] == b['source'] == shared.ARMS['A'] and a['archive_sha256'] == b['archive_sha256']
            and a['sdk'] == b['sdk'] and a['bundle_prefix'] == b['bundle_prefix'] and a['fixture'] != b['fixture'],
            'mapped SDK/archive/source/fixture differs')
    additions = {PREFIX+'accessibility_capture.py',PREFIX+'test_accessibility_capture.py'}
    require(set(new['helpers']) == set(old['helpers'])|additions
            and all(new['helpers'][n] == h for n,h in old['helpers'].items() if n != BUILDER)
            and all(shared.sha(shared.REPO/n) == h for n,h in new['helpers'].items()), 'mapped build helpers changed')
    builder = source_mapping((old_root/'helpers'/BUILDER).read_text(),(build_root/'helpers'/BUILDER).read_text(),'builder')
    require(set(a['client']) == set(b['client']), 'mapped client membership changed')
    left,right = old_root/'A-simulator/client',build_root/'A-simulator/client'
    require((right/'HumanObservation.swift').read_bytes() ==
            accessibility_capture.render_human((left/'HumanObservation.swift').read_bytes(),shared.sha(left/'HumanObservation.swift')),
            'new human observer is not the exact overlay')
    for name in a['client']:
        if name == 'HumanObservation.swift': continue
        if name in ['UIKitTransitions.plist','SwiftUITransitions.plist']:
            before = plistlib.loads((left/name).read_bytes()); after = plistlib.loads((right/name).read_bytes())
            require(before['TransitionFixture'] == a['fixture'] and after['TransitionFixture'] == b['fixture'],
                    'mapped client fixture identity differs')
            before['TransitionFixture'] = b['fixture']
            require(before == after, 'mapped client metadata changed beyond fixture identity')
        else:
            require(a['client'][name] == b['client'][name], 'mapped client changed: '+name)
    proof = dict(old_build_root=str(old_root),old_plan_sha256=prior['build_plan'],old_receipt_sha256=prior['build_receipt'],
        new_build_root=str(build_root),new_plan_sha256=shared.sha(build_root/'plan.json'),
        new_receipt_sha256=shared.sha(build_root/'A-simulator/build-result.json'),source=a['source'],
        source_archive_sha256=a['archive_sha256'],sdk_tree_sha256=build.digest(a['sdk']),
        old_fixture=a['fixture'],new_fixture=b['fixture'],old_products_sha256=build.digest(old_product['products']),
        new_products_sha256=build.digest(new_product['products']),human_before_sha256=a['client']['HumanObservation.swift'],
        human_after_sha256=b['client']['HumanObservation.swift'],builder_unchanged_module=builder,
        new_build_helpers=new['helpers'],release_acceptance=False,gate_closures=[])
    return proof,old,old_product


def bind(root, build_root, compiled, products, device, helpers):
    root = Path(root).resolve(strict=True)
    files = {}
    for name in FILES:
        path = root/name
        require(path.is_file() and not path.is_symlink(), 'predecessor evidence missing or linked: ' + name)
        files[name] = shared.sha(path)
    plan = shared.read(root/'plan.json'); result = shared.read(root/'cells/UIKit/summary.json')
    native = shared.read(root/'cells/UIKit/native-summary.json'); worker = shared.read(root/'fresh-worker-quiescence.json')
    cleanup = shared.read(root/'cleanup-readback.json'); review = shared.read(root/'review.json')
    outcome = shared.read(root/'outcome-review.json'); controls = shared.read(root/'controls.json')
    require(plan['cells'] == ['UIKit'] and plan['release_acceptance'] is False and plan['gate_closures'] == []
            and all(result[k] == 'PASS' for k in ['state', 'scenario', 'evidence', 'cleanup'])
            and result['release_acceptance'] is False and result['gate_closures'] == []
            and result['restored_at'] < result['cleanup_deadline'], 'predecessor is not a restored capture-only PASS')
    mapping = None; reference = compiled; reference_products = products
    if compiled.get('public_accessibility_inventory') is True:
        mapping,reference,reference_products = mapped_build(plan,build_root,compiled,products)
    else:
        require(plan['build_root'] == str(build_root) and plan['build_plan'] == shared.sha(build_root/'plan.json')
                and plan['build_receipt'] == shared.sha(build_root/'A-simulator/build-result.json'), 'predecessor build differs')
    require(plan['device'] == device and device['state'] == 'Shutdown', 'predecessor device differs')
    source = reference['arms']['A-simulator']; identity = result['identity']
    require(identity['source'] == source['source'] and identity['fixture'] == source['fixture']
            and identity['bundle'] == reference_products['products']['UIKit']['bundle']
            and identity['framework'] == 'UIKit' and identity['tracking'] == 'automatic'
            and native['identity'] == identity and worker['native_identity'] == identity, 'predecessor native identity differs')
    require(set(native['transitions']) == {'pop.finish','pop.cancel','dismiss.finish','dismiss.cancel'}
            and all(v['native']['state'] == 'NATIVE_QUALIFIED' for v in native['transitions'].values()),
            'predecessor native transition inventory incomplete')
    # Baseline semantic limitations remain classified in the original native record.
    # Capturing a transition does not establish its SDK/backend ownership contract.
    require(worker['worker_stopped'] and worker['runner_stopped'] and worker['all_published_requests_complete']
            and worker['tool_pending'] is None and worker['local_pending'] is None and not worker['uncertain_attempts']
            and len(worker['requests']) == 11 and all(r['input_complete'] for r in worker['requests'])
            and worker['plan_sha256'] == files['plan.json'], 'predecessor input is not quiescent and complete')
    require(all(cleanup[k] is True for k in ['worker_quiescent','runner_stopped','app_and_data_absent',
            'original_pid_absent','non_task_inventory_unchanged','actual_session_absence']), 'predecessor cleanup incomplete')
    require(review['state'] == controls['state'] == outcome['state'] == 'PASS'
            and review['reviewer'] == outcome['reviewer'] == '/root/c06_runtime_plan'
            and review['plan_sha256'] == controls['plan_sha256'] == files['plan.json']
            and review['controls_sha256'] == files['controls.json']
            and outcome['summary']['sha256'] == files['cells/UIKit/summary.json']
            and outcome['cleanup']['sha256'] == files['cleanup-readback.json'], 'predecessor review binding differs')
    require(shared.tree(root/'helpers') == plan['helpers'] == controls['helpers'], 'predecessor frozen helpers changed')
    permitted_changes = {QUALIFIER, PREFIX+'test_capture_qualification.py'}
    additions = {PREFIX+'capture_predecessor.py', PREFIX+'test_capture_predecessor.py'}
    if mapping is not None:
        permitted_changes |= {BUILDER, ORACLE, PREFIX+'capture_predecessor.py', PREFIX+'test_capture_predecessor.py'}
        additions |= {PREFIX+'accessibility_capture.py'}
        mapping['oracle_unchanged_module'] = source_mapping((root/'helpers'/ORACLE).read_text(),(shared.REPO/ORACLE).read_text(),'oracle')
        mapping['old_oracle_sha256'] = plan['helpers'][ORACLE]
        mapping['new_oracle_sha256'] = helpers[ORACLE]
    require(set(plan['helpers']) <= set(helpers) and set(helpers)-set(plan['helpers']) <= additions
            and all(helpers[n] == h for n,h in plan['helpers'].items() if n not in permitted_changes),
            'predecessor native helper surface changed')
    runtime = runtime_mapping((root/'helpers'/QUALIFIER).read_text(), (shared.REPO/QUALIFIER).read_text())
    result = dict(root=str(root),files=files,source=identity['source'],fixture=identity['fixture'],device=device,
        previous_qualifier_sha256=plan['helpers'][QUALIFIER],current_qualifier_sha256=helpers[QUALIFIER],
        runtime_functions=runtime,release_acceptance=False,gate_closures=[])
    if mapping is not None:result['build_mapping'] = mapping
    return result


def verify(plan, compiled, products):
    predecessor = plan.get('predecessor')
    if predecessor is None:
        require(plan['cells'] in [['UIKit'], ['UIKit','SwiftUI']], 'SwiftUI-only plan lacks predecessor')
        return
    require(plan['cells'] == ['SwiftUI'], 'predecessor only belongs to a SwiftUI-only plan')
    actual = bind(predecessor['root'], Path(plan['build_root']), compiled, products, plan['device'], plan['helpers'])
    require(actual == predecessor, 'predecessor receipt changed')


def summary_path(root, plan):
    predecessor = plan.get('predecessor')
    return Path(predecessor['root'])/'cells/UIKit/summary.json' if predecessor else root/'cells/UIKit/summary.json'

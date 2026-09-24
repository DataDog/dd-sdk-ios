"""Reuse one completed UIKit mechanism qualification before a SwiftUI-only cell."""
import ast
from pathlib import Path
import build

shared = build.shared
require = build.require
PREFIX = 'tools/multi-scene/interactive-transitions/'
QUALIFIER = PREFIX + 'capture_qualification.py'
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
    require(plan['build_root'] == str(build_root) and plan['build_plan'] == shared.sha(build_root/'plan.json')
            and plan['build_receipt'] == shared.sha(build_root/'A-simulator/build-result.json'), 'predecessor build differs')
    require(plan['device'] == device and device['state'] == 'Shutdown', 'predecessor device differs')
    source = compiled['arms']['A-simulator']; identity = result['identity']
    require(identity['source'] == source['source'] and identity['fixture'] == source['fixture']
            and identity['bundle'] == products['products']['UIKit']['bundle']
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
    require(set(plan['helpers']) <= set(helpers) and set(helpers)-set(plan['helpers']) <= additions
            and all(helpers[n] == h for n,h in plan['helpers'].items() if n not in permitted_changes),
            'predecessor native helper surface changed')
    mapping = runtime_mapping((root/'helpers'/QUALIFIER).read_text(), (shared.REPO/QUALIFIER).read_text())
    return dict(root=str(root),files=files,source=identity['source'],fixture=identity['fixture'],device=device,
        previous_qualifier_sha256=plan['helpers'][QUALIFIER],current_qualifier_sha256=helpers[QUALIFIER],
        runtime_functions=mapping,release_acceptance=False,gate_closures=[])


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

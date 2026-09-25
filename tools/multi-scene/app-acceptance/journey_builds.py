"""Read-only reuse of the two qualified F08 capture products."""
import ast
import copy
import datetime
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess

import capture_build
from capture_build import sha
from capture_contract import loads
from journey_contract import require

ARMS = dict(baseline='62f64d7b655bdc83f3036c4ad81090a270f6202b', candidate='c9faed816a1d4828d7d8c4b64acae01119425889')


def module(path):
    spec = importlib.util.spec_from_file_location('frozen_capture_source_guard', path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def product(app, manifest):
    app = Path(app).resolve(strict=True)
    files = {str(p.relative_to(app)):sha(p) for p in app.rglob('*') if p.is_file() and not p.is_symlink()}
    links = {str(p.relative_to(app)):os.readlink(p) for p in app.rglob('*') if p.is_symlink()}
    require(files == {name:row['sha256'] for name,row in manifest['files'].items()} and links == manifest['symlinks'],
            'complete installed product changed')
    require(all((app/name).resolve(strict=True).is_relative_to(app) for name in links), 'installed symlink escapes app')
    info = plistlib.loads((app/'Info.plist').read_bytes())
    require(info['DTSDKName'] == 'iphonesimulator27.1' and info['MinimumOSVersion'] == '18.0'
            and info['UIApplicationSceneManifest']['UIApplicationSupportsMultipleScenes'] is False,
            'ordinary app product identity differs')
    return dict(files=len(files), mach_o=len(manifest['mach_o']), bundle_id=info['CFBundleIdentifier'],
                executable=info['CFBundleExecutable'], application_id=info['RUMReleaseValidationApplicationID'],
                app_version=info['CFBundleShortVersionString'], sdk_version=manifest['sdk_version'])


PROTECTED = ['Datadog/Datadog.xcodeproj/project.pbxproj', 'xcconfigs/Datadog.local.xcconfig']
TRANSITION = 'DatadogRUM/MultiSceneSupport/Results/navigation-documentation-consolidation-20260924.json'


def retained_guards(original, incorporated, remaining):
    require(remaining == PROTECTED and set(original) == set(incorporated) | set(PROTECTED),
            'authorized documentation protection transition differs')
    require(len(incorporated) == 10 and all(name.endswith('.md') and name.startswith('DatadogRUM/')
            and original[name] == {'sha256':digest} for name,digest in incorporated.items()),
            'old document guard not bound to incorporated input')
    return {name:original[name] for name in PROTECTED}


def document_binding(current, committed, index, dirty):
    require(not dirty and current == committed and index == committed,
            'incorporated documentation differs from committed worktree/index')
    return current


def current_documents(repo, names):
    repo=Path(repo);names=sorted(names)
    def git(*args):
        return subprocess.check_output(['git',*args],cwd=repo,timeout=15)
    dirty=git('status','--porcelain','--untracked-files=no','--',*names)
    current={name:sha(repo/name) for name in names}
    committed={name:hashlib.sha256(git('show','HEAD:'+name)).hexdigest() for name in names}
    staged={name:hashlib.sha256(git('show',':'+name)).hexdigest() for name in names}
    hashes=document_binding(current,committed,staged,dirty)
    # A helper-only checkpoint may advance HEAD without changing this document
    # tree. Bind the actual last commit touching these paths, not any later HEAD.
    commit=git('log','-1','--format=%H','--',*names).decode().strip()
    require(len(commit)==40,'incorporated document tree commit missing')
    return dict(commit=commit,sha256=hashes,worktree_and_index_clean=True)


def documentation_transition(repo, preparation):
    path=Path(repo)/TRANSITION;value=json.loads(path.read_text())['main_integration']
    root=Path(value['evidence_root']);inputs=root/'original-input-manifest.json';receipt=root/'integration.json'
    incorporated=json.loads(inputs.read_text());integration=json.loads(receipt.read_text())
    require(integration['state']=='SIGNED_COMMITTED' and integration['signature']=='G'
            and integration['source_commit']==value['source_commit']
            and integration['protected_paths_unchanged']==2 and value['original_input_hashes_verified']==10,
            'documentation incorporation unqualified')
    require(subprocess.run(['git','merge-base','--is-ancestor',integration['commit'],'HEAD'],cwd=repo,
                           capture_output=True,timeout=15).returncode==0, 'documentation incorporation not in checkout')
    guards=retained_guards(preparation['protected_paths'],incorporated['paths'],value['remaining_protected_paths'])
    documents=current_documents(repo,incorporated['paths'])
    proof=dict(current_documents=documents,transition={'path':str(path),'sha256':sha(path)},original_inputs={'path':str(inputs),'sha256':sha(inputs)},
               integration={'path':str(receipt),'sha256':sha(receipt)},remaining_protected_paths=PROTECTED,
               incorporated_document_paths=list(incorporated['paths']),original_manifests_modified=False)
    return guards,proof


# This transition is restricted to the reviewed host-only correctness policy and
# its binding adapter. Compiler inputs, products and other helpers cannot vary.
RUNTIME_TRANSITION_FILES = {
    'smoke-definition.json', 'smoke_contract.py', 'smoke_driver.py', 'smoke_runtime.py',
    'journey_workflow.py', 'journey_builds.py', 'journey_session.py', 'journey_driver.py', 'journey_readiness.py',
    'journey_contract.py', 'capture_io.py', 'capture_contract.py', 'capture_build.py',
}


SIGNED_IN_TRANSITION_FILES = {'smoke_contract.py','smoke_driver.py','smoke_runtime.py',
    'journey_workflow.py','journey_builds.py','journey_driver.py','journey_phases.py'}
SIGNED_IN_ADDITIONS = {'signed-in-definition.json','signed_in_account.py'}
DASHBOARD_TRANSITION_FILES = SIGNED_IN_TRANSITION_FILES | {'browser_contract.py','journey_session.py'}
DASHBOARD_ADDITIONS = SIGNED_IN_ADDITIONS | {'journey_release.py'}


def binding_split(original, current):
    before, after = ast.parse(original), ast.parse(current)
    expected = copy.deepcopy(before)
    binder = next(node for node in expected.body if isinstance(node, ast.FunctionDef) and node.name == 'bind')
    split = ast.parse('def bind_sources(root, definition, preparation, arm=None):\n    pass\n').body[0]
    split.body = binder.body[4:]
    binder.body = binder.body[:4] + ast.parse('return bind_sources(root, definition, preparation, arm)').body
    expected.body.insert(expected.body.index(binder) + 1, split)
    require(ast.dump(expected) == ast.dump(after), 'source binder differs beyond the qualified function split')


def runtime_helpers(original, current, changes, reviewed, allowed):
    require(set(changes) == allowed and allowed <= set(original) and set(current) == set(original),
            'runtime transition path inventory differs')
    for name, previous in original.items():
        if name in changes:
            row = changes[name]
            require(set(row) == {'before', 'after'} and row['before'] == previous
                    and row['after'] == current[name] == reviewed.get(name) and previous != current[name],
                    'runtime helper transition differs from reviewed source')
        else:
            require(current[name] == previous, 'non-transition helper changed')
    return changes


def transition_guard(root, original, definition, binding):
    require(set(binding) == {'path', 'sha256'}, 'runtime transition binding differs')
    path = Path(binding['path'])
    require(path.is_absolute() and not path.is_symlink() and sha(path) == binding['sha256'],
            'runtime transition manifest changed')
    transition = loads(path.read_bytes())
    require(transition['schema_version'] == 1 and transition['state'] == 'REVIEWED_HOST_ONLY_REUSE'
            and transition['build_root'] == str(root)
            and transition['definition_sha256'] == sha(root/'definition.json')
            and transition['completion_sha256'] == sha(root/'completion.json'), 'runtime transition build differs')
    review_path = Path(transition['review']['path'])
    require(sha(review_path) == transition['review']['sha256'], 'runtime transition review changed')
    review = loads(review_path.read_bytes())
    require(review['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan',
            'runtime transition unreviewed')
    controls_path = Path(review['controls']['path'])
    require(sha(controls_path) == review['controls']['sha256'], 'runtime transition controls changed')
    controls = loads(controls_path.read_bytes())
    require(controls['state'] == 'PASS_OFFLINE_ONLY' and controls['source_sha256'] == review['source_sha256'],
            'runtime transition review/control sources differ')
    here = Path(__file__).resolve().parent
    dashboard=transition.get('scope')=='signed-in-dashboard-v2'
    signed_in=dashboard or transition.get('scope')=='signed-in-smoke-v1'
    allowed = {str(here/name) for name in (DASHBOARD_TRANSITION_FILES if dashboard else SIGNED_IN_TRANSITION_FILES if signed_in else RUNTIME_TRANSITION_FILES)}
    current = {name:sha(name) for name in definition['qualified_helper_sha256']}
    if signed_in:
        added={str(here/name):sha(here/name) for name in (DASHBOARD_ADDITIONS if dashboard else SIGNED_IN_ADDITIONS)}
        require(transition.get('additions')==added and all(review['source_sha256'].get(k)==v for k,v in added.items()),
                'signed-in added helpers differ from reviewed sources')
    changes = runtime_helpers(definition['qualified_helper_sha256'], current, transition['changes'],
                              review['source_sha256'], allowed)
    require(review['changes_sha256'] == hashlib.sha256(
        json.dumps(changes, sort_keys=True, separators=(',', ':')).encode()).hexdigest(),
        'runtime transition review does not bind the changes')
    if signed_in:
        require(ast.dump(ast.parse(original.read_text()))==ast.dump(ast.parse(Path(capture_build.__file__).read_text())),
                'signed-in reuse changed the frozen source binder')
    else:binding_split(original.read_text(), Path(capture_build.__file__).read_text())
    preparation = loads((root/'preparation.json').read_bytes())
    guard, preparation = capture_build.bind_sources(root, definition, preparation)
    return guard, preparation


def verify(build_root, arm, completion_sha256, *, installed=None, runtime_transition=None):
    root = Path(build_root).resolve(strict=True)
    require(arm in ARMS and sha(root/'completion.json') == completion_sha256, 'unbound capture build completion')
    completion = json.loads((root/'completion.json').read_text())
    bound = completion['arms'][arm]
    require(completion['state'] == 'TWO_SOURCE_BOUND_CAPTURE_PRODUCTS_QUALIFIED' and bound['source'] == ARMS[arm],
            'wrong qualified source')
    require(datetime.datetime.fromisoformat(bound['finished_at']) < datetime.datetime.fromisoformat(bound['deadline']),
            'original product qualification was late')
    for name,digest in bound['receipts'].items():require(sha(root/arm/name) == digest, 'original build receipt changed')
    require(not (root/arm/'late-product-publication.json').exists(), 'original product publication expired')
    original = root/'capture-build-before-filelist-correction.py'
    definition = json.loads((root/'definition.json').read_text())
    require(sha(original) == definition['adapter_sha256'], 'original source guard changed')
    if runtime_transition is None:
        guard, preparation = module(original).bind(root)
    else:
        guard, preparation = transition_guard(root, original, definition, runtime_transition)
    freeze = json.loads((root/arm/'build-input-freeze.json').read_text())
    # Old receipts remain immutable. Only the authorized non-compiler document
    # guards change; the frozen guard still verifies both user files and every
    # original app, SDK, dependency and generated compiler input.
    if getattr(guard,'has_documentation_transition',False):
        transition=guard.source_guard(arm, freeze['workspace_sha256'])['workspace_transition']
    else:
        retained,transition=documentation_transition(guard.P.REPO,preparation)
        original_protected=preparation['protected_paths']
        try:
            preparation['protected_paths']=retained
            guard.source_guard(arm, freeze['workspace_sha256'])
        finally:
            preparation['protected_paths']=original_protected
    paths = preparation['arms'][arm]
    require(guard.generated_inventory(Path(paths['app']),Path(paths['sdk'])) == freeze['generated']
            and guard.sdk_membership(Path(paths['sdk'])) == freeze['sdk_membership'], 'qualified compiler inputs changed')
    compiler = json.loads((root/arm/'capture-compiler-receipt.json').read_text())
    require(compiler['status'] == 'PASS', 'capture compiler membership unqualified')
    archives = json.loads((root/arm/'sdk-archive-build-receipt.json').read_text())
    for archive in archives['archives'].values():
        require(sha(archive['path']) == archive['sha256'] and
                all(sha(path) == value for path,value in archive['objects'].items()), 'qualified SDK archive/object changed')
    manifest = json.loads((root/arm/'installed-bundle-freeze.json').read_text())
    require(manifest['source_revision'] == ARMS[arm], 'product source differs')
    identity = product(installed or manifest['app_path'], manifest)
    if runtime_transition is not None:
        transition_guard(root, original, definition, runtime_transition)
    return dict(state='SOURCE_AND_PRODUCT_REUSED', arm=arm, source=ARMS[arm], manifest=manifest,
                identity=identity, application_path=manifest['app_path'], native_launches=0, workspace_transition=transition,
                runtime_transition=runtime_transition)

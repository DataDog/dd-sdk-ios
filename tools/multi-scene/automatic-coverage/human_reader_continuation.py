"""Opt-in compiler-bound continuation for the two-stage public reader.

Historical accepted cells use their preserved source. New cells retain the same
semantic oracle and execution path, with an explicit source verifier throughout.
"""
import argparse
import hashlib
from pathlib import Path
import signal

import human_supported_readiness as ready
import human_swiftui_refresh as refresh
import reviewer_assignment

s = ready.supported
require = s.require
KIND = 'S2_TWO_STAGE_READER_CONTINUATION'
OWNER_NOT_SUPPLIED = object()
READER_PATHS = {refresh.READER, 'tools/multi-scene/interactive-transitions/test_accessibility_capture.py'}
ADAPTERS = ready.ADAPTERS + [
    'tools/multi-scene/automatic-coverage/human_reader_continuation.py',
    'tools/multi-scene/automatic-coverage/test_human_reader_continuation.py',
    'tools/multi-scene/acceptance/reviewer_assignment.py']


def binary(reference):
    path = Path(reference['path'])
    require(path.is_file() and not path.is_symlink() and s.reference(path) == reference,
            'bound binary/source changed')
    return path


def component(reference):
    review = ready.bound_read(reference)
    require(review['state'] == 'PASS' and not review['findings']
            and review['native_admitted'] is False and review['human_invitation'] is False,
            'reader component review does not qualify native execution')
    bindings = review['bindings']['source_and_contract_hashes']
    for name, digest in bindings.items():
        require(s.sha(name) == digest, 'reviewed reader or semantic contract changed')
    require(all(str(ready.REPO/name) in bindings for name in READER_PATHS),
            'reader review lacks source/test closure')
    return review


def original_helpers(old, folder, reader_review):
    bindings = reader_review['bindings']['source_and_contract_hashes']
    for name, digest in old['helpers'].items():
        require(s.sha(folder/'helpers'/name) == digest, 'original helper snapshot changed')
        if name in READER_PATHS:
            require(s.sha(ready.REPO/name) == bindings[str(ready.REPO/name)],
                    'new reader is not the reviewed replacement')
        elif name not in (ready.CONTRACT, ready.RUNTIME, ready.SESSIONS):
            require(s.sha(ready.REPO/name) == digest, 'nonreader helper changed: ' + name)


def source(stopped_reference, refresh_reference, reader_reference, selected):
    require(selected in ready.continuation.UNIVERSE[4:], 'only two remaining split cells are admitted')
    review = component(reader_reference)
    stopped = ready.bound_read(stopped_reference)
    require(stopped['selected'] == ready.SELECTED and stopped['state'] == 'STOPPED_BEFORE_HUMAN_INPUT'
            and stopped['human_prompts'] == 0 and stopped['cleanup'] == 'PASS', 'wrong predecessor')
    old = ready.bound_read(stopped['plan'])
    folder = Path(stopped['plan']['path']).parent
    original_helpers(old, folder, review)
    ready.load_module('human_sessions', folder/'helpers'/ready.SESSIONS)
    runner = ready.load_module('two_stage_automatic_runtime', folder/'helpers'/ready.RUNTIME)
    require(runner.shared.REPO == ready.REPO, 'foreign runtime repository')
    base = runner.human_sessions.original(Path(old['original_build_root']), runner,
        allow_backend_decoder_update=True, allow_fixture_refresh=True)
    new = ready.bound_read(refresh_reference)
    new_root = Path(refresh_reference['path']).parent
    require(refresh.verify(new_root) == new, 'new compiler source differs')
    previous = ready.bound_read(old['observer_refresh'])
    require(new['prior_refresh'] == previous['prior_refresh']
            and new['original'] == previous['original']
            and new['toolchains'] == previous['toolchains'], 'compiler ancestry changed')
    for key in refresh.prior.KEYS:
        before, after = previous['arms'][key], new['arms'][key]
        require({k:v for k,v in before.items() if k != 'client'}
                == {k:v for k,v in after.items() if k != 'client'}, 'SDK/source identity changed')
        require(set(before['client']) == set(after['client'])
                and {n for n in before['client'] if before['client'][n] != after['client'][n]}
                == {'HumanObservation.swift'}, 'nonreader fixture changed')
    oracle, measurement = runner.refresh_oracle(Path(old['original_build_root']), base, new_root)
    require(measurement == old['measurement']
            and s.sha(folder/'helpers'/ready.CONTRACT) == hashlib.sha256(oracle).hexdigest(),
            'semantic/native oracle changed')
    runner.human_sessions.activate_contract_file(folder/'helpers'/ready.CONTRACT,
                                                  old['helpers'][ready.CONTRACT], runner)
    product = refresh.product(new_root, selected['build'])
    return runner, old, product, new['arms'][selected['build']]['revision']


def helpers(old, stopped):
    values = ready.helper_binding(old, stopped)
    values.update({name: s.reference(ready.REPO/name) for name in READER_PATHS | set(ADAPTERS)})
    return values


def historical_readers(stopped_reference):
    stopped = ready.bound_read(stopped_reference); old = ready.bound_read(stopped['plan'])
    folder = Path(stopped['plan']['path']).parent/'helpers'
    result = []
    for name in sorted(READER_PATHS):
        copied = s.reference(folder/name)
        require(copied['sha256'] == old['helpers'][name], 'historical reader snapshot changed')
        binary(copied)
        result.append(dict(original=dict(path=str(ready.REPO/name),sha256=old['helpers'][name]), copied=copied))
    return result


def compare_prefix(plans, old, stopped_reference):
    stopped = ready.bound_read(stopped_reference)
    previous = ready.bound_read(old['observer_refresh'])
    expected_helpers = ready.helper_binding(old, stopped)
    for plan in plans:
        key = plan['selected']['build']
        expected_product = old['products'][key+'-SwiftUI-single']
        require(plan['stopped'] == stopped_reference
                and plan['original_build_root'] == old['original_build_root']
                and plan['contract'] == old['contract']
                and plan['effect_observation'] == ready.human_effect_recapture.CONTRACT
                and plan['product'] == expected_product
                and plan['source'] == previous['arms'][key]['revision'],
                'accepted cell belongs to another source comparison')
        require(all(plan['helpers'][name] == expected_helpers[name] for name in old['helpers']),
                'accepted source comparison helper differs')
        require(refresh.s.product(expected_product['path'], bundle=expected_product['bundle'])
                == expected_product['product'], 'accepted original product changed')


def interaction_owner(owner, review):
    require(isinstance(owner,str) and owner.startswith('/root/')
            and owner not in (review['reviewer'],reviewer_assignment.LEGACY_REVIEWER),
            'independent actual interaction owner required')


def verify(root, *, reviewed=True, tool_owner=OWNER_NOT_SUPPLIED):
    runtime = Path(root)/'runtime'
    plan = s.read(runtime/'runtime-plan.json')
    require(plan['kind'] == KIND and plan['native_admitted'] is False and plan['gates_closed'] == [],
            'foreign continuation')
    preserved = historical_readers(plan['stopped'])
    require(plan['historical_readers'] == preserved, 'historical reader substitution changed')
    selected, completed, accepted_plans = ready.continuation.selection(ready.bound_read(plan['accepted_owner']),
                                                                     preserved_helpers=preserved)
    require(plan['selected'] == selected and plan['completed'] == completed,
            'completed prefix or selected cell changed')
    runner, old, product, revision = source(plan['stopped'], plan['reader_refresh'], plan['reader_review'], selected)
    compare_prefix(accepted_plans, old, plan['stopped'])
    require(plan['source'] == revision and plan['product'] == product
            and plan['original_build_root'] == old['original_build_root']
            and plan['contract'] == old['contract'] and plan['effect_observation'] == ready.human_effect_recapture.CONTRACT
            and plan['readiness'] == ready.readiness_profile('split')
            and plan['capture_seconds'] == 120 and plan['ready_seconds'] == 600
            and plan['coverage_owner'] == str(ready.REPO/'DatadogRUM/MultiSceneSupport/Results/S2-coverage-remaining-preparation.json')
            and plan['helpers'] == helpers(old, ready.bound_read(plan['stopped'])), 'frozen continuation inputs changed')
    for member in plan['helpers'].values(): binary(member)
    binary(plan['skill'])
    tools = ready.bound_read(plan['tool_contract'])
    require(tools['kind'] == 'AVAILABLE_XCODE_TOOL_DESCRIPTIONS'
            and {x['name'] for x in tools['tools']} == {'mcp__xcode__'+n for n in s.TOOLS.values()},
            'supported tool inventory changed')
    if reviewed:
        controls = s.read(runtime/'controls.json'); review = s.read(runtime/'review.json')
        digest = s.sha(runtime/'runtime-plan.json')
        reviewer_assignment.require_reviewer(review, digest, runtime)
        require(review['state'] == controls['state'] == 'PASS' and review['findings'] == []
                and review['plan_sha256'] == controls['plan_sha256'] == digest
                and review['controls_sha256'] == s.sha(runtime/'controls.json')
                and controls['helpers'] == plan['helpers'], 'missing or stale native review/controls')
        if tool_owner is not OWNER_NOT_SUPPLIED: interaction_owner(tool_owner,review)
    return runner, plan


def admit(args):
    # Apply the assigned-role check inside the validated review boundary.
    return ready.admit(args,verifier=lambda root: verify(root,tool_owner=args.tool_owner))


def cell(args):
    runtime = args.root.resolve()/'runtime'
    stage_ref = s.reference(runtime/'native-admission.json')
    review_ref = s.reference(runtime/'review.json')
    stage = ready.bound_read(stage_ref)
    runner, _ = verify(args.root,tool_owner=stage['tool_owner'])
    def consumed_stage(actual):
        binary(stage_ref); binary(review_ref)
        require(actual == stage, 'native admission changed after owner qualification')
        interaction_owner(actual['tool_owner'],ready.bound_read(review_ref))
    binary(stage_ref); binary(review_ref)
    with runner.human_processes.shared_commands(runner.shared):
        return ready.execute(args,verifier=verify,stage_validator=consumed_stage)


def main():
    parser = argparse.ArgumentParser(); parser.add_argument('command', choices=['verify','admit','run','cell'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--preflight', type=Path); parser.add_argument('--tool-owner')
    args = parser.parse_args()
    if args.command == 'verify': verify(args.root, reviewed=False)
    elif args.command == 'admit': admit(args)
    elif args.command == 'run': return ready.run(args, verifier=verify, entrypoint=__file__)
    else:
        signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(RuntimeError('supervisor stopped execution')))
        return cell(args)
    return 0


if __name__ == '__main__': raise SystemExit(main())

"""Prepare the first untouched split baseline; never admit or launch it."""
import argparse
import json
from pathlib import Path

import human_reader_continuation as c


def component_review(reference):
    review = c.ready.bound_read(reference)
    c.require(review['state'] == 'PASS' and review['findings'] == []
              and review['native_admitted'] is False and review['human_invitation'] is False,
              'source continuation component is unreviewed')
    controls = c.ready.bound_read(review['bindings']['controls'])
    c.require(controls['state'] == 'PASS'
              and review['controls_sha256'] == review['bindings']['controls']['sha256']
              and controls['source_bindings'] == review['bindings']['source_bindings'],
              'component controls differ from review')
    for path, digest in controls['source_bindings'].items():
        c.binary(dict(path=path,sha256=digest))
    return review


def export_reference(path):
    path = Path(path)
    c.require(path.is_absolute() and path.is_file() and not path.is_symlink(),
              'live export must be an absolute regular file')
    return c.s.reference(c.binary(c.s.reference(path)))


def instructions(skill, tool_contract):
    # The operator must supply the actual fresh export. Tool descriptions do not
    # replace a required skill; missing instructions cannot allocate a run root.
    skill = export_reference(skill)
    tools_ref = export_reference(tool_contract)
    c.require(Path(skill['path']).read_text().strip(), 'empty live interaction instructions')
    tools = c.ready.bound_read(tools_ref)
    c.require(tools['kind'] == 'AVAILABLE_XCODE_TOOL_DESCRIPTIONS'
              and {x['name'] for x in tools['tools']} == {'mcp__xcode__'+n for n in c.s.TOOLS.values()},
              'wrong live interaction tool inventory')
    return skill, tools_ref


def publication_join(plan, reference):
    c.binary(reference)
    c.require(c.ready.bound_read(reference) == plan, 'prepared plan changed during publication')
    for name in ('component_review','compiler_review','plan_factory','reader_review',
                 'reader_refresh','skill','tool_contract'):
        c.binary(plan[name])
    component_review(plan['component_review'])


def prepare(args):
    root = args.root.resolve(); runtime = root/'runtime'
    c.require(not root.exists(), 'output root already consumed')
    skill, tools = instructions(args.skill, args.tool_contract)
    component_ref = c.s.reference(args.component_review)
    review = component_review(component_ref)
    compiler_ref = c.s.reference(args.compiler_review)
    compiler = c.ready.bound_read(compiler_ref)
    reader = c.s.reference(args.reader_review); refreshed = c.s.reference(args.refresh/'refresh-plan.json')
    c.require(compiler['state'] == 'PASS' and compiler['findings'] == []
              and compiler['bindings']['reader_review'] == reader
              and compiler['bindings']['refresh_plan'] == refreshed
              and review['bindings']['compiler_review'] == compiler_ref,
              'compiler and component review belong to different sources')
    stopped = c.s.reference(args.stopped_result)
    owner_path = c.ready.REPO/'DatadogRUM/MultiSceneSupport/Results/S2-coverage-remaining-preparation.json'
    owner = c.s.read(owner_path); preserved = c.historical_readers(stopped)
    selected, completed, accepted = c.ready.continuation.selection(owner,preserved_helpers=preserved)
    c.require(selected == c.ready.continuation.UNIVERSE[4], 'only first remaining baseline is prepared')
    runner, old, product, revision = c.source(stopped,refreshed,reader,selected)
    c.compare_prefix(accepted,old,stopped)
    plan = dict(schema_version=1,kind=c.KIND,selected=selected,source=revision,product=product,
                completed=completed,coverage_owner=str(owner_path),stopped=stopped,
                original_build_root=old['original_build_root'],helpers=c.helpers(old,c.ready.bound_read(stopped)),
                historical_readers=preserved,reader_refresh=refreshed,reader_review=reader,
                component_review=component_ref,compiler_review=compiler_ref,
                plan_factory=c.s.reference(__file__),skill=skill,tool_contract=tools,
                contract=old['contract'],effect_observation=c.ready.human_effect_recapture.CONTRACT,
                readiness=c.ready.readiness_profile('split'),capture_seconds=120,ready_seconds=600,
                budget_basis='Unchanged accepted operational cutoffs; SDK observer durations remain diagnostic.',
                native_admitted=False,gates_closed=[])
    runtime.mkdir(parents=True)
    c.s.save(runtime/'accepted-owner.json',owner)
    plan['accepted_owner'] = c.s.reference(runtime/'accepted-owner.json')
    for name in ('cells','operator'): (runtime/name).mkdir()
    plan['publication'] = runner.transport.publication_preflight(runtime)
    c.s.save(runtime/'runtime-plan.json',plan)
    plan_ref = c.s.reference(runtime/'runtime-plan.json')
    c.verify(root,reviewed=False)
    publication_join(plan,plan_ref)
    runner.human_operator.publish(runtime/'operator',{'instruction':'Preparing. No gestures are requested.'})
    publication_join(plan,plan_ref)
    c.verify(root,reviewed=False)
    return dict(state='PREPARED_ONLY',plan=plan_ref,native_admitted=False,gates_closed=[])


def main():
    parser = argparse.ArgumentParser()
    for name in ('root','skill','tool-contract','component-review','compiler-review','reader-review','refresh','stopped-result'):
        parser.add_argument('--'+name,type=Path,required=True)
    print(json.dumps(prepare(parser.parse_args())))


if __name__ == '__main__': main()

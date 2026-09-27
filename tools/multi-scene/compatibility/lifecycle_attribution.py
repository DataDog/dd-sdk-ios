#!/usr/bin/env python3
"""Observe three failed Integration cases without changing their acceptance oracle."""
import argparse
import json
from pathlib import Path
import re
import time
import uuid
import clean_integration as clean

runner = clean.runner
shared = runner.shared
require = runner.require
FLAG = 'DD_RUM_LIFECYCLE_DIAGNOSTICS'
FIXTURE = 'Datadog/IntegrationUnitTests/AppRunner/AppRunner.swift'
MARKER = 'RUM_INTEGRATION_LIFECYCLE '


def helpers():
    return {**clean.helpers(), **{str(p.resolve()): shared.sha(p) for p in
            [Path(__file__), Path(__file__).with_name('test_lifecycle_attribution.py')]}}


def activation(built, reference, fixture):
    observed = built['compiler_conditions']
    require(set(observed) == set(reference), 'diagnostic compiler target inventory differs')
    for target, row in observed.items():
        require(set(row['conditions']) == set(reference[target]['conditions']) | {FLAG}, 'unadmitted compiler condition change')
    uses = {(target, path) for target, row in built['compiler']['swift'].items() for path in row['inputs']
            if FLAG in Path(path).read_text()}
    require(uses == {('DatadogIntegrationTests', str(fixture))}, 'diagnostic flag affects foreign compiled source')


def observations(text, selected):
    """Retain actual ordered JSON records, joined to their native XCTest boundaries."""
    boundary = re.compile(r"^Test Case '-\[(DatadogIntegrationTests)\.([^ ]+) ([^]]+)\]' (started|passed|failed)(?:\.| \(.+ seconds\)\.)$")
    cases = {}; owners = {}; active = None
    for line in text.splitlines():
        match = boundary.fullmatch(line)
        if match:
            target, cls, method, status = match.groups(); identifier = f'{target}/{cls}/{method}()'
            require(identifier in selected, 'foreign diagnostic test case')
            if status == 'started':
                require(active is None and identifier not in cases, 'duplicate or overlapping test start')
                active = identifier; cases[active] = dict(runs={}, result=None)
            else:
                require(active == identifier, 'test finish has no matching start')
                cases[active]['result'] = status; active = None
        elif MARKER in line:
            require(line.startswith(MARKER) and active is not None, 'unowned or altered diagnostic line')
            record = json.loads(line[len(MARKER):]); run = record.get('run')
            require(isinstance(run, str) and str(uuid.UUID(run)).upper() == run.upper(), 'invalid AppRunner identity')
            require(type(record.get('sequence')) is int and type(record.get('mainThread')) is bool
                    and isinstance(record.get('phase'), str), 'invalid diagnostic schema')
            require(run not in owners or owners[run] == active, 'AppRunner reused across tests')
            owners[run] = active; records = cases[active]['runs'].setdefault(run, [])
            require(record['sequence'] == len(records) + 1, 'missing, reordered or duplicate diagnostic record')
            for key in ['view', 'lastView']:
                if key in record:
                    require(record['mainThread'] and set(record[key]) == {'controller', 'window', 'scene'}
                            and all(isinstance(v, str) and v for v in record[key].values()), 'unsafe or incomplete topology')
            records.append(record)
    require(active is None and sorted(cases) == sorted(selected), 'incomplete native test boundaries')
    for case in cases.values():
        require(case['runs'] and case['result'] in ['passed', 'failed'], 'test has no observations or result')
        for records in case['runs'].values():
            require(records[0]['phase'] == 'launch' and records[-1]['phase'] == 'teardown'
                    and sum(r['phase'] == 'result' for r in records) == 1, 'incomplete AppRunner lifecycle')
    return cases


def verify(root):
    runner.inputs.DEFINITION = root / 'input-definition.json'
    runner.DEFINITION = root / 'execution-input-definition.json'
    definition, base, frozen = runner.verify(root)
    binding = shared.read(root / 'diagnostic-plan.json')
    require(binding['helpers'] == helpers() and binding['execution_plan'] == shared.sha(root / 'execution-plan.json'),
            'diagnostic binding changed')
    for path, digest in binding['references'].items():
        require(shared.sha(Path(path)) == digest, 'diagnostic source/reference changed')
    spec = definition['diagnostic']
    require(len(base['cells']) == 1 and base['cells'][0]['id'] == 'integration' and len(spec['selected']) == 3,
            'expanded diagnostic cell scope')
    for row in definition['discovery_non_cases']['DatadogIntegrationTests']:
        require(shared.sha(root / 'workspace' / row['source']) == row['sha256'], 'discovery helper source changed')
    folder = root / 'cells/integration'
    if (folder / 'built.json').exists():
        activation(shared.read(folder / 'built.json'), spec['reference_compiler_conditions'], root / 'workspace' / FIXTURE)
    if (folder / 'selection.json').exists():
        require(shared.read(folder / 'selection.json')['identifiers'] == sorted(spec['selected']), 'diagnostic selection differs')
    return definition, base, frozen


def run(root):
    definition, base, frozen = verify(root)
    review = shared.read(root / 'diagnostic-review.json'); controls = shared.read(root / 'diagnostic-controls.json')
    require(review['state'] == controls['state'] == 'PASS' and review['reviewer'] == '/root/c06_runtime_plan'
            and review['plan_sha256'] == controls['plan_sha256'] == shared.sha(root / 'diagnostic-plan.json')
            and review['controls_sha256'] == shared.sha(root / 'diagnostic-controls.json')
            and controls['helpers'] == helpers(), 'unreviewed diagnostic admission')
    now = time.time(); limit = definition['latest_completion_epoch']; spec = definition['clean_simulator']
    require(now + base['budgets_seconds']['cell'] + spec['creation_budget_seconds'] + spec['deletion_budget_seconds'] < limit,
            'whole diagnostic reservation does not fit')
    stage = dict(at=now, deadline=limit, plan_sha256=shared.sha(root / 'execution-plan.json'),
                 review_sha256=shared.sha(root / 'diagnostic-review.json'))
    shared.save(root / 'module-stage.json', stage, exclusive=True)
    result = dict(state='RUNNING', cells=[], observation='INCOMPLETE', cleanup='NOT_STARTED', gate_closures=[])
    created = None
    def save(): shared.save(root / 'module-summary.json', result)
    save()
    try:
        created = clean.create(root, definition, limit)
        fresh, cell = clean.runtime_cell(base, created)
        runner.TEST_BUILD_FLAGS += ' -D ' + FLAG
        row = runner.run_cell(root, cell, definition, fresh, frozen, stage, verify_inputs=verify)
        result['cells'].append(row); save()
        folder = root / 'cells/integration'
        require((folder / 'decoded.json').exists() and row['evidence'] == 'PASS', 'missing exact executed evidence')
        cases = observations((folder / 'execute.log').read_text(), definition['diagnostic']['selected'])
        decoded = shared.read(folder / 'decoded.json')
        require(sorted(decoded['cases']) == sorted(cases), 'diagnostic cases differ from xcresult')
        shared.save(root / 'observations.json', cases, exclusive=True)
        result.update(state='OBSERVED', observation='COMPLETE', observations_sha256=shared.sha(root / 'observations.json'))
    except Exception as error: result.update(state='STOPPED', failure=type(error).__name__ + ': ' + str(error))
    finally:
        try:
            if created: clean.remove(root, definition, created, limit)
            else: require(not (root / 'create-device.log').exists(), 'unclassified simulator creation')
            verify(root)
            require(all(c['cleanup'] == 'PASS' for c in result['cells']) and time.time() < limit, 'incomplete original cleanup')
            result['cleanup'] = 'PASS'
        except Exception as error: result.update(state='STOPPED', cleanup='INVALID', cleanup_failure=str(error))
        result['finished_at'] = time.time(); save()
        print(json.dumps({k: v for k, v in result.items() if k != 'cells'}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--root', type=Path, required=True)
    run(parser.parse_args().root.resolve())

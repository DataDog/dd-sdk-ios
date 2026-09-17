#!/usr/bin/env python3
"""Validate finite release gates and refresh their compact progress/plan tables."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re


def validate(register):
    gates = register['gates']
    by_id = {g['id']: g for g in gates}
    if len(by_id) != len(gates):
        raise ValueError('duplicate gate ID')
    allowed = {'OPEN', 'CLOSED', 'ENVIRONMENT BLOCKED', 'REGRESSION BLOCKED',
               'REVIEW BLOCKED', 'INCONCLUSIVE'}
    for g in gates:
        for field in ['deliverable', 'owner', 'decisive_test', 'environment']:
            if not g.get(field):
                raise ValueError(g['id'] + ': missing ' + field)
        if g.get('status') not in allowed:
            raise ValueError(g['id'] + ': unsupported status')
        if g['status'] == 'CLOSED' and not g.get('evidence'):
            raise ValueError(g['id'] + ': closed without evidence')
        if g['id'].startswith('T') and not g.get('completion_mode'):
            raise ValueError(g['id'] + ': telemetry completion mode missing')
        if any(d not in by_id for d in g['dependencies']):
            raise ValueError(g['id'] + ': unknown dependency')
    done = set()
    def visit(ident, active):
        if ident in active:
            raise ValueError('dependency cycle at ' + ident)
        if ident in done:
            return
        for dependency in by_id[ident]['dependencies']:
            visit(dependency, active | {ident})
        done.add(ident)
    for ident in by_id:
        visit(ident, set())
    return by_id


def plan_rows(text, gates):
    seen = set()
    def replace(match):
        ident = match.group(1)
        if ident not in gates:
            raise ValueError('plan contains unknown gate ' + ident)
        if ident in seen:
            raise ValueError('duplicate plan row ' + ident)
        seen.add(ident)
        g = gates[ident]
        dependency = ', '.join(g['dependencies']) or 'None'
        if ident == 'F06':
            dependency = 'All preceding gates'
        mode = ' — ' + g['completion_mode'] if g['completion_mode'] else ''
        fields = [ident, g['deliverable'] + mode, g['owner'], dependency,
                  g['decisive_test'], g['environment'], g['status']]
        return '| ' + ' | '.join(v.replace('|', '\\|') for v in fields) + ' |'
    result = re.sub(r'^\| ([A-Z]\d{2}) \|.*$', replace, text, flags=re.M)
    if seen != set(gates):
        raise ValueError('gates missing from plan: ' + ', '.join(sorted(set(gates) - seen)))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='Refresh only PLAN.md gate rows and Results/release-progress.json')
    args = parser.parse_args()
    base = Path(__file__).resolve().parents[2] / 'DatadogRUM/MultiSceneSupport'
    register = json.loads((base / 'release-gates.json').read_text())
    gates = validate(register)
    counts = dict(sorted(Counter(g['status'] for g in gates.values()).items()))
    progress = {'schema_version': 1, 'candidate_revision': register['candidate_revision'],
                'gate_count': len(gates), 'counts': counts,
                'closed': [g['id'] for g in gates.values() if g['status'] == 'CLOSED'],
                'remaining': [{'id': g['id'], 'status': g['status'], 'owner': g['owner'],
                               'dependencies': g['dependencies']} for g in gates.values() if g['status'] != 'CLOSED']}
    plan = base / 'PLAN.md'
    rendered = plan_rows(plan.read_text(), gates)
    if args.update:
        plan.write_text(rendered)
        (base / 'Results').mkdir(exist_ok=True)
        (base / 'Results/release-progress.json').write_text(json.dumps(progress, indent=2) + '\n')
    elif rendered != plan.read_text():
        raise ValueError('PLAN.md gate rows are stale; run --update')
    print(json.dumps({'total': len(gates), 'counts': counts, 'closed': progress['closed']}))


if __name__ == '__main__':
    main()

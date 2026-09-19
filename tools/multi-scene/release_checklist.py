#!/usr/bin/env python3
"""Validate finite release gates and refresh their compact progress/plan tables."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re


RELEASE_IDS = ('S1', 'S2', 'S3')
GATE_STATUSES = {
    'OPEN', 'CLOSED', 'ENVIRONMENT BLOCKED', 'REGRESSION BLOCKED',
    'REVIEW BLOCKED', 'INCONCLUSIVE', 'CONDITIONAL',
}


def _require_nonempty(owner, fields, label=None):
    for field in fields:
        if not isinstance(owner.get(field), str) or not owner[field].strip():
            raise ValueError((label or owner.get('id', 'release requirement')) + ': missing ' + field)


def _validate_releases(register):
    releases = register.get('releases')
    if releases is None:
        return ()
    if not isinstance(releases, list):
        raise ValueError('releases must be a list')
    by_id = {release.get('id'): release for release in releases}
    if len(by_id) != len(releases):
        raise ValueError('duplicate release ID')
    if set(by_id) != set(RELEASE_IDS):
        raise ValueError('releases must define S1, S2, and S3')
    for release in releases:
        if release['id'] not in RELEASE_IDS:
            raise ValueError('unknown release ID')
        _require_nonempty(release, ['name', 'shipping_rule'])
        if release.get('deadline') is not None and not isinstance(release['deadline'], str):
            raise ValueError(release['id'] + ': invalid deadline')
    return tuple(releases)


def _validate_release_requirements(gates, releases):
    if not releases:
        if any('release_requirements' in gate for gate in gates):
            raise ValueError('release requirements require releases')
        return
    release_ids = {release['id'] for release in releases}
    instances = {}
    for gate in gates:
        requirements = gate.get('release_requirements')
        if not isinstance(requirements, dict) or not requirements:
            raise ValueError(gate['id'] + ': release requirements missing')
        for release_id, requirement in requirements.items():
            if release_id not in release_ids:
                raise ValueError(gate['id'] + ': unknown release requirement')
            if not isinstance(requirement, dict):
                raise ValueError(gate['id'] + ': invalid release requirement')
            _require_nonempty(requirement, ['scope', 'decisive_test', 'environment'], gate['id'])
            if requirement.get('status') not in GATE_STATUSES:
                raise ValueError(gate['id'] + ': unsupported release status')
            if not isinstance(requirement.get('required'), bool):
                raise ValueError(gate['id'] + ': release requirement must declare required')
            if not isinstance(requirement.get('dependencies'), list):
                raise ValueError(gate['id'] + ': release dependencies must be a list')
            if requirement['status'] == 'CLOSED' and not requirement.get('evidence'):
                raise ValueError(gate['id'] + ': closed release requirement without evidence')
            if gate['id'] == 'F01' and release_id != 'S3':
                raise ValueError('F01 is S3-only')
            if gate['id'] == 'F04' and release_id == 'S2' and requirement['required']:
                raise ValueError('F04 cannot be required in S2')
            instances[release_id + ':' + gate['id']] = requirement

    for source, requirement in instances.items():
        source_release = source.partition(':')[0]
        for dependency in requirement['dependencies']:
            if not isinstance(dependency, str) or not re.fullmatch(r'S[123]:[A-Z]\d{2}', dependency):
                raise ValueError(source + ': dependency must be fully qualified')
            dependency_release = dependency.partition(':')[0]
            if source_release in {'S1', 'S2'} and dependency_release == 'S3':
                raise ValueError(source + ': S1/S2 cannot depend on S3')
            if dependency not in instances:
                raise ValueError(source + ': unknown release dependency ' + dependency)
            if source_release == 'S2' and requirement['required'] and dependency == 'S2:F04':
                raise ValueError(source + ': required S2 dependency on F04 is forbidden')

    done = set()
    def visit(ident, active):
        if ident in active:
            raise ValueError('release dependency cycle at ' + ident)
        if ident in done:
            return
        for dependency in instances[ident]['dependencies']:
            visit(dependency, active | {ident})
        done.add(ident)
    for ident in instances:
        visit(ident, set())


def validate(register):
    gates = register['gates']
    by_id = {g['id']: g for g in gates}
    if len(by_id) != len(gates):
        raise ValueError('duplicate gate ID')
    for g in gates:
        for field in ['deliverable', 'owner', 'decisive_test', 'environment']:
            if not g.get(field):
                raise ValueError(g['id'] + ': missing ' + field)
        if g.get('status') not in GATE_STATUSES:
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
    _validate_release_requirements(gates, _validate_releases(register))
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
            dependency = 'Release-specific dependencies below' if g.get('release_requirements') else 'All preceding gates'
        mode = ' — ' + g['completion_mode'] if g['completion_mode'] else ''
        fields = [ident, g['deliverable'] + mode, g['owner'], dependency,
                  g['decisive_test'], g['environment']]
        requirements = g.get('release_requirements')
        if requirements:
            release_status = ', '.join(
                release_id + ' ' + ('required' if requirement['required'] else 'follow-up') + ' ' + requirement['status']
                for release_id, requirement in sorted(requirements.items())
            )
            fields.append(release_status)
        evidence = '[register evidence](release-gates.json)' if g.get('evidence') else 'Pending'
        fields.extend([g['status'], evidence])
        return '| ' + ' | '.join(v.replace('|', '\\|') for v in fields) + ' |'
    result = re.sub(r'^\| ([A-Z]\d{2}) \|.*$', replace, text, flags=re.M)
    if seen != set(gates):
        raise ValueError('gates missing from plan: ' + ', '.join(sorted(set(gates) - seen)))
    return result


ACTIVE_DOCUMENTS = [
    '.continue-here.md', 'DatadogRUM/MULTI_SCENE_SUPPORT.md',
    *['DatadogRUM/MultiSceneSupport/' + name + '.md' for name in [
        'PLAN', 'ASSESSMENT', 'EXPERIMENTS', 'TOOLING_RUNBOOK',
        'PRODUCTION_SAFETY_REVIEW', 'REVIEW_TRIAGE', 'COMPONENT_REVIEW',
        'STABLE_API_REVIEW', 'SUPPORT_GUIDE', 'FINAL_COMPATIBILITY',
        'DEFERRED_SINGLE_SCENE_EXTRACTION', 'HUMAN_ACCEPTANCE']],
]


def prose(text):
    """Ignore quoted code/history when checking active links and instructions."""
    result, fence = [], None
    for line in text.splitlines():
        marker = re.match(r'^\s*('+chr(96)+r'{3,}|~{3,})', line)
        if marker:
            value = marker.group(1)
            if fence is None:
                fence = value
            elif value[0] == fence[0] and len(value) >= len(fence):
                fence = None
            continue
        if fence is None:
            result.append(line)
    return '\n'.join(result)


def anchors(text):
    result = set(re.findall(r'<a\s+id="([^"]+)"', text))
    occurrences = Counter()
    for heading in re.findall(r'^#{1,6}\s+(.+)$', prose(text), re.M):
        heading = re.sub(r'\[([^]]+)\]\([^)]+\)', r'\1', heading)
        slug = re.sub(r'[^\w\- ]', '', heading.lower()).replace(' ', '-')
        occurrence = occurrences[slug]
        occurrences[slug] += 1
        result.add(slug + ('-' + str(occurrence) if occurrence else ''))
    return result


def validate_links(repo, names):
    from urllib.parse import unquote
    checked, target_anchors = 0, {}
    for name in names:
        source = repo / name
        for raw in re.findall(r'\]\((<[^>]+>|[^)\s]+)\)', prose(source.read_text())):
            value = unquote(raw.strip('<>'))
            if re.match(r'^[a-zA-Z][\w+.-]*://', value) or value.startswith('mailto:'):
                continue
            path, _, fragment = value.partition('#')
            path = re.sub(r':\d+$', '', path)
            target = (source.parent / path).resolve() if path else source.resolve()
            if not target.exists():
                raise ValueError(name + ': missing link target ' + value)
            # Frozen snapshots retain their original links. Exact archived line
            # locators were verified in the consolidation manifest; do not open
            # frozen history or configuration as part of routine restart checks.
            if fragment and target.suffix == '.md' and 'Archive' not in target.parts:
                if target not in target_anchors:
                    target_anchors[target] = anchors(target.read_text())
                if fragment not in target_anchors[target]:
                    raise ValueError(name + ': missing heading ' + value)
            checked += 1
    return checked


def validate_documents(repo, gates):
    texts = {name: prose((repo / name).read_text()) for name in ACTIVE_DOCUMENTS}
    index = texts['DatadogRUM/MultiSceneSupport/EXPERIMENTS.md']
    ids = re.findall(r'^\| (?:<a id="exp-\d{3}"></a>)?(EXP-\d{3}) \|', index, re.M)
    records = repo / 'DatadogRUM/MultiSceneSupport/Experiments'
    active_ids = {int(value) for path in records.glob('EXP-[0-9]*.md')
                  for value in re.findall(r'^## EXP-(\d{3})\b', path.read_text(), re.M)}
    last = max(active_ids, default=len(ids))
    if not ids or len(ids) != len(set(ids)) or ids != [f'EXP-{n:03}' for n in range(1, last+1)]:
        raise ValueError('experiment index IDs must be unique and contiguous')
    for row in index.splitlines():
        if row.startswith('| <a id="exp-'):
            fields = re.split(r'(?<!\\)\|', row)[1:-1]
            if len(fields) != 5 or not all(field.strip() for field in fields):
                raise ValueError('experiment index requires five nonempty fields')
            if any(ident not in gates for ident in fields[1].strip().split(', ')):
                raise ValueError('experiment index references unknown gate')
            if not re.search(r'\[record\]\(', fields[-1]):
                raise ValueError('experiment index requires an exact record link')
    for name, text in texts.items():
        if name.endswith(('MULTI_SCENE_SUPPORT.md', 'EXPERIMENTS.md')):
            if re.search(r'^#{1,6}\s+(?:Resume here|Current checkpoint|Next experiment)', text, re.M | re.I):
                raise ValueError(name + ': restart cursor belongs only in .continue-here.md')
        if name != 'DatadogRUM/MultiSceneSupport/PLAN.md':
            if re.search(r'\b\d+\s*/\s*\d+\s+(?:release\s+)?gates?\s+closed', text, re.I):
                raise ValueError(name + ': gate totals belong in generated progress')
    history = 'DatadogRUM/MultiSceneSupport/Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md'
    return {'links': validate_links(repo, ACTIVE_DOCUMENTS + [history]), 'experiments': len(ids)}


def progress_document(register, gates):
    counts = dict(sorted(Counter(g['status'] for g in gates.values()).items()))
    progress = {'schema_version': 1, 'candidate_revision': register['candidate_revision'],
            'gate_count': len(gates), 'counts': counts,
            'closed': [g['id'] for g in gates.values() if g['status'] == 'CLOSED'],
            'remaining': [{'id': g['id'], 'status': g['status'], 'owner': g['owner'],
                           'dependencies': g['dependencies']} for g in gates.values() if g['status'] != 'CLOSED']}
    releases = register.get('releases')
    if not releases:
        return progress
    release_progress = {}
    for release in releases:
        release_id = release['id']
        requirements = [(gate_id, gate['release_requirements'][release_id], gate)
                        for gate_id, gate in gates.items() if release_id in gate['release_requirements']]
        required = [(gate_id, requirement, gate) for gate_id, requirement, gate in requirements if requirement['required']]
        optional = [(gate_id, requirement, gate) for gate_id, requirement, gate in requirements
                    if not requirement['required'] and requirement['status'] != 'CLOSED']
        release_progress[release_id] = {
            'name': release['name'],
            'deadline': release['deadline'],
            'shipping_rule': release['shipping_rule'],
            'required': {
                'count': len(required),
                'closed': sum(requirement['status'] == 'CLOSED' for _, requirement, _ in required),
                'remaining': [
                    {'id': release_id + ':' + gate_id, 'status': requirement['status'], 'owner': gate['owner'],
                     'dependencies': requirement['dependencies']}
                    for gate_id, requirement, gate in required if requirement['status'] != 'CLOSED'
                ],
            },
            'optional_follow_ups': [
                {'id': release_id + ':' + gate_id, 'status': requirement['status'], 'owner': gate['owner'],
                 'dependencies': requirement['dependencies']}
                for gate_id, requirement, gate in optional
            ],
        }
    progress['release_progress'] = release_progress
    return progress


def render_release_views(text, register, progress):
    releases = register.get('releases')
    if not releases:
        return text
    marker = re.compile(r'<!-- release-views:start -->.*?<!-- release-views:end -->', re.S)
    if len(marker.findall(text)) != 1:
        raise ValueError('PLAN.md must contain exactly one release-views marker pair')
    gates = {gate['id']: gate for gate in register['gates']}
    lines = [
        '<!-- release-views:start -->',
        '### Candidate release views',
        '',
        '| Release | Deadline | Shipping rule | Required | Closed | Remaining |',
        '| --- | --- | --- | ---: | ---: | ---: |',
    ]
    for release in releases:
        summary = progress['release_progress'][release['id']]['required']
        lines.append('| {id} — {name} | {deadline} | {shipping_rule} | {count} | {closed} | {remaining} |'.format(
            id=release['id'], name=release['name'], deadline=release['deadline'] or 'TBD',
            shipping_rule=release['shipping_rule'], count=summary['count'], closed=summary['closed'],
            remaining=len(summary['remaining'])))
    for release_id in ('S1', 'S2'):
        lines.extend([
            '',
            '### ' + release_id + ' release gates',
            '',
            '| Gate | Scoped deliverable | Owner | Qualified dependencies | Decisive test | Environment | Status | Evidence |',
            '| --- | --- | --- | --- | --- | --- | --- | --- |',
        ])
        rows = []
        for gate_id, gate in gates.items():
            requirement = gate['release_requirements'].get(release_id)
            if requirement is None:
                continue
            dependencies = ', '.join(requirement['dependencies']) or 'None'
            status = ('required' if requirement['required'] else 'follow-up') + ' · ' + requirement['status']
            evidence = '[register evidence](release-gates.json)' if requirement.get('evidence') else 'Pending'
            rows.append([
                release_id + ':' + gate_id, gate['deliverable'] + ': ' + requirement['scope'], gate['owner'], dependencies,
                requirement['decisive_test'], requirement['environment'], status, evidence,
            ])
        lines.extend('| ' + ' | '.join(value.replace('|', '\\|') for value in row) + ' |' for row in rows)
    lines.append('<!-- release-views:end -->')
    return marker.sub('\n'.join(lines), text)


def check_progress(path, expected):
    if not path.exists() or json.loads(path.read_text()) != expected:
        raise ValueError('release-progress.json is stale; run --update')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='Refresh generated PLAN gate rows and release-progress.json, then validate documents')
    args = parser.parse_args()
    base = Path(__file__).resolve().parents[2] / 'DatadogRUM/MultiSceneSupport'
    register = json.loads((base / 'release-gates.json').read_text())
    gates = validate(register)
    progress = progress_document(register, gates)
    counts = progress['counts']
    plan = base / 'PLAN.md'
    rendered = render_release_views(plan_rows(plan.read_text(), gates), register, progress)
    if args.update:
        plan.write_text(rendered)
        (base / 'Results').mkdir(exist_ok=True)
        (base / 'Results/release-progress.json').write_text(json.dumps(progress, indent=2) + '\n')
    elif rendered != plan.read_text():
        raise ValueError('PLAN.md gate rows are stale; run --update')
    check_progress(base / 'Results/release-progress.json', progress)
    documents = validate_documents(base.parents[1], gates)
    print(json.dumps({'documents': documents, 'total': len(gates), 'counts': counts, 'closed': progress['closed']}))


if __name__ == '__main__':
    main()

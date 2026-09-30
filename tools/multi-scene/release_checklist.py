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


def _validate_execution_packages(register):
    """Keep a finite release queue complete without counting preparation as proof."""
    gates = {gate['id']: gate for gate in register['gates']}
    for release in register.get('releases', []):
        if 'execution_packages' not in release:
            continue
        packages = release['execution_packages']
        if not isinstance(packages, list) or not packages:
            raise ValueError('execution packages must be a nonempty list')
        seen_ids, assigned = set(), set()
        for package in packages:
            _require_nonempty(package, ['id', 'title', 'owner', 'decisive_test', 'environment', 'budget'])
            if package['id'] in seen_ids:
                raise ValueError('duplicate execution package')
            seen_ids.add(package['id'])
            members = package.get('gates')
            if not isinstance(members, list) or not members:
                raise ValueError('execution package must name its gates')
            if not isinstance(package.get('dependencies'), list):
                raise ValueError('execution package dependencies missing')
            for ident in members + package['dependencies']:
                requirement = gates.get(ident, {}).get('release_requirements', {}).get(release['id'])
                if not requirement or not requirement['required']:
                    raise ValueError('execution package references unknown or nonrequired gate')
            for ident in members:
                if ident in assigned:
                    raise ValueError('gate assigned to multiple execution packages')
                assigned.add(ident)
        remaining = {ident for ident, gate in gates.items()
                     if (requirement := gate.get('release_requirements', {}).get(release['id']))
                     and requirement['required'] and requirement['status'] != 'CLOSED'}
        if not remaining <= assigned:
            raise ValueError('required open gates missing from execution packages')


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
    _validate_execution_packages(register)
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
    'tools/multi-scene/acceptance/README.md',
    *['DatadogRUM/MultiSceneSupport/' + name + '.md' for name in [
        'PLAN', 'ASSESSMENT', 'EXPERIMENTS', 'TOOLING_RUNBOOK',
        'PRODUCTION_SAFETY_REVIEW', 'REVIEW_TRIAGE', 'COMPONENT_REVIEW',
        'STABLE_API_REVIEW', 'SUPPORT_GUIDE', 'FINAL_COMPATIBILITY',
        'DEFERRED_SINGLE_SCENE_EXTRACTION', 'HUMAN_ACCEPTANCE', 'REMAINING_WORK']],
]


DOCUMENT_ROOT = 'DatadogRUM/MultiSceneSupport/'
TOOLING_DIRECTORY = DOCUMENT_ROOT + 'Tooling'
RUNBOOK = DOCUMENT_ROOT + 'TOOLING_RUNBOOK.md'
ACCEPTANCE_ROUTER = 'tools/multi-scene/acceptance/README.md'
ACCEPTANCE_DIRECTORY = 'tools/multi-scene/acceptance/docs'
DOCUMENT_BUDGETS = {
    RUNBOOK: (200, 1800),
    '.continue-here.md': (85, 900),
    ACCEPTANCE_ROUTER: (180, 1600),
}
PROCEDURE_BUDGET = (320, 3600)
HISTORICAL_DOCUMENTS = [
    DOCUMENT_ROOT + 'Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md',
    DOCUMENT_ROOT + 'Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md',
]


def procedure_documents(repo):
    """Discover nested procedures so newly added pages cannot escape link checks."""
    paths = sorted((repo / TOOLING_DIRECTORY).rglob('*.md'))
    if not paths:
        raise ValueError('runbook must route to at least one procedure')
    paths += sorted((repo / ACCEPTANCE_DIRECTORY).rglob('*.md'))
    if any(path.is_symlink() for path in paths):
        raise ValueError('procedure documents must be regular files, not symlinks')
    return [str(path.relative_to(repo)) for path in paths]


def validate_reading_budget(name, text, budget):
    # Include tables and code fences: moving a journal into either does not make
    # the entry point cheaper to read. The word bound also catches giant lines.
    lines, words = budget
    if len(text.splitlines()) > lines or len(text.split()) > words:
        raise ValueError(name + ': reading budget exceeded; consolidate or route to its owner')


def validate_document_layout(repo, procedures):
    from urllib.parse import unquote
    for name, budget in DOCUMENT_BUDGETS.items():
        validate_reading_budget(name, (repo / name).read_text(), budget)
    routes = {}
    for name in (RUNBOOK, ACCEPTANCE_ROUTER):
        router = repo / name
        routed = set()
        for raw in re.findall(r'\]\((<[^>]+>|[^)\s]+)\)', prose(router.read_text())):
            value = unquote(raw.strip('<>'))
            if re.match(r'^[a-zA-Z][\w+.-]*:', value):
                continue
            path = value.partition('#')[0]
            if path:
                routed.add((router.parent / path).resolve())
        routes[name] = routed
    for name in procedures:
        path = repo / name
        router = ACCEPTANCE_ROUTER if name.startswith(ACCEPTANCE_DIRECTORY + '/') else RUNBOOK
        if path.resolve() not in routes[router]:
            raise ValueError(name + ': procedure missing from runbook routes')
        validate_reading_budget(name, path.read_text(), PROCEDURE_BUDGET)

    # Long exact progress paragraphs in multiple active summaries caused drift.
    # Tables/short common rules may share vocabulary; narratives have one owner.
    seen = {}
    for name in ['.continue-here.md', DOCUMENT_ROOT + 'ASSESSMENT.md',
                 DOCUMENT_ROOT + 'PRODUCTION_SAFETY_REVIEW.md']:
        for paragraph in re.split(r'\n\s*\n', prose((repo / name).read_text())):
            normalized = ' '.join(paragraph.split())
            if len(normalized.split()) < 60 or normalized.startswith(('#', '|')):
                continue
            if normalized in seen and seen[normalized] != name:
                raise ValueError(name + ': duplicated narrative from ' + seen[normalized])
            seen[normalized] = name


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


def validate_active_policy(texts):
    # These previously active requirements contradict the approved September25
    # rule. Historical baseline protocols/results retain their original wording.
    patterns = [r'\brequired performance benchmarking\b',
                r'\b(?:must|required|mandatory)\s+(?:run\s+)?(?:a\s+)?(?:paired\s+)?(?:application[- ]|strict[- ])(?:performance|timing)\b',
                r'\bdoes not replace F06.{0,100}\bpaired performance\b',
                r'\buse one bounded representative before/after application comparison\b']
    for name in (DOCUMENT_ROOT + 'PLAN.md', DOCUMENT_ROOT + 'FINAL_COMPATIBILITY.md'):
        # PLAN's generated register evidence includes historical scope; only its
        # active policy prose is checked here. Register requirements own gates.
        text = re.sub(r'<!-- release-views:start -->.*?<!-- release-views:end -->', '', texts[name], flags=re.S)
        normalized = ' '.join(line for line in text.splitlines() if not line.startswith('|')).replace('\n', ' ')
        if any(re.search(pattern, normalized, re.I) for pattern in patterns):
            raise ValueError(name + ': active policy contradicts the September25 measurement rule')


def validate_documents(repo, gates):
    procedures = procedure_documents(repo)
    names = ACTIVE_DOCUMENTS + procedures
    validate_document_layout(repo, procedures)
    texts = {name: prose((repo / name).read_text()) for name in names}
    validate_active_policy(texts)
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
    return {'links': validate_links(repo, names + HISTORICAL_DOCUMENTS),
            'experiments': len(ids), 'procedures': len(procedures)}


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
        release = next(value for value in releases if value['id'] == release_id)
        if release.get('execution_packages'):
            lines.extend(['', '### ' + release_id + ' execution packages', '',
                          'These packages share runs; individual gate verdicts remain separate. Closed evidence is reused.', '',
                          '| Package / gates | Owner | Dependencies | Decisive evidence | Environment | Bound | Gates still open |',
                          '| --- | --- | --- | --- | --- | --- | ---: |'])
            for package in release['execution_packages']:
                remaining = sum(gates[ident]['release_requirements'][release_id]['status'] != 'CLOSED'
                                for ident in package['gates'])
                row = [package['title'] + ' (' + ', '.join(package['gates']) + ')', package['owner'],
                       ', '.join(package['dependencies']) or 'None', package['decisive_test'],
                       package['environment'], package['budget'], str(remaining)]
                lines.append('| ' + ' | '.join(value.replace('|', '\\|') for value in row) + ' |')
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
    import release_work
    remaining_path = base / 'REMAINING_WORK.md'
    owners = release_work.read_owners(base.parents[1])
    remaining = release_work.render(register, owners)
    cursor_path = base.parents[1] / '.continue-here.md'
    cursor_original = cursor_path.read_text()
    cursor = release_work.render_cursor(cursor_original, owners['execution'])
    progress = progress_document(register, gates)
    counts = progress['counts']
    plan = base / 'PLAN.md'
    rendered = render_release_views(plan_rows(plan.read_text(), gates), register, progress)
    if args.update:
        plan.write_text(rendered)
        (base / 'Results').mkdir(exist_ok=True)
        (base / 'Results/release-progress.json').write_text(json.dumps(progress, indent=2) + '\n')
        remaining_path.write_text(remaining)
        if cursor != cursor_original:
            if cursor_path.read_text() != cursor_original:
                raise ValueError('cursor changed during generation; reread before updating')
            cursor_path.write_text(cursor)
    elif rendered != plan.read_text():
        raise ValueError('PLAN.md gate rows are stale; run --update')
    if cursor_path.read_text() != cursor:
        raise ValueError('cursor execution summary is stale; run --update')
    check_progress(base / 'Results/release-progress.json', progress)
    if not remaining_path.exists() or remaining_path.read_text() != remaining:
        raise ValueError('REMAINING_WORK.md is stale; run --update')
    documents = validate_documents(base.parents[1], gates)
    print(json.dumps({'documents': documents, 'total': len(gates), 'counts': counts, 'closed': progress['closed']}))


if __name__ == '__main__':
    main()

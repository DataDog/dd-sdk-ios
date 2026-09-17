#!/usr/bin/env python3
"""Full-context P04 discriminator; separate binary, no ABBA timing rerun."""
import argparse
import json
from pathlib import Path
import shutil
import run


def prepare(attempt, manifest):
    directory = attempt / 'candidate'
    source = directory / 'FocusedSources'
    source.mkdir(exist_ok=True)
    for file in (run.HERE / 'Fixture').iterdir():
        shutil.copyfile(file, source / file.name)
    shutil.copyfile(run.HERE / 'FocusedChecks.swift', source / 'FocusedChecks.swift')
    text = (source / 'App.swift').read_text()
    text = text.replace('if mode == "internal" {', 'if mode == "focused" {')
    text = text.replace('result["internal"] = InternalFixture.run(window: window!)', 'result["focused"] = FocusedChecks.run(window: window!)')
    (source / 'App.swift').write_text(text)
    spec = json.loads((directory / 'project.json').read_text())
    target = json.loads(json.dumps(spec['targets']['FixtureScene']))
    target['sources'] = ['FocusedSources']
    target['settings']['base']['SWIFT_OBJC_BRIDGING_HEADER'] = 'FocusedSources/AllocationCounter.h'
    target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.datadoghq.exp160.candidate.focused'
    spec['targets']['FixtureFocused'] = target
    spec['schemes']['EXP160Focused'] = {'build': {'targets': {'FixtureFocused': 'all'}}}
    (directory / 'project.json').write_text(json.dumps(spec, indent=2))
    run.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate-focused.log')
    command = ['xcodebuild', 'build', '-project', str(directory / 'EXP160.xcodeproj'), '-scheme', 'EXP160Focused', '-configuration', 'Release', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
    manifest['commands'].append(command)
    run.call(command, log=directory / 'build-focused.log')
    app = directory / 'derived/Build/Products/Release-iphonesimulator/FixtureFocused.app'
    binary = app / 'FixtureFocused'
    manifest['builds']['candidate']['Focused'] = {'app': str(app), 'sha256': run.digest(binary), 'uuid': run.call(['dwarfdump', '--uuid', str(binary)]).strip(), 'deployment_target': '15.0', 'fixture': run.fingerprint(source), 'scope': 'P04 assertions only; original timing fixture and binaries unchanged'}
    run.save(attempt, manifest)


def run_matrix(attempt, manifest):
    for version in manifest['devices']:
        run.run_one(attempt, manifest, 'candidate', 'Focused', version, 'focused', 'full-context-P04')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['prepare', 'run', 'all'])
    parser.add_argument('--attempt', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads((args.attempt / 'manifest.json').read_text())
    if args.stage in ['prepare', 'all']:
        prepare(args.attempt, manifest)
    if args.stage in ['run', 'all']:
        run_matrix(args.attempt, manifest)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Actual OS background/foreground discriminator for EXP-160 C03 on iOS26.5.

Build a separately identified variant. The ABBA fixture and binaries stay frozen.
"""
import argparse
import json
from pathlib import Path
import shutil
import time
import run


def app_variant(text):
    text = text.replace('static let manual = mode == "manual"', 'static let manual = mode == "lifecycle-manual"')
    text = text.replace('static var started = false', 'static var started = false\n    static var observers: [NSObjectProtocol] = []')
    text = text.replace('''        Datadog.initialize(with:''', '''        for notification in [UIApplication.didEnterBackgroundNotification, UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { value in
                EventStore.shared.append(["type": "lifecycle", "name": value.name.rawValue])
            })
        }
        Datadog.initialize(with:''', 1)
    begin = text.index('        if mode == "automatic" || manual {')
    end = text.index('        if mode == "dispatch" || mode == "disabled" {', begin)
    replacement = '''        if mode.hasPrefix("lifecycle-") {
            if !(await waitFor { views("Home").count == 1 }) { failures.append("initial Home missing") }
            marker("BeforeBackground")
            if !(await waitFor { EventStore.shared.snapshot().filter { ["action", "resource"].contains($0["type"] as? String ?? "") }.count == 2 }) { failures.append("initial markers missing") }
            try? JSONSerialization.data(withJSONObject: ["run_id": value("--run-id")]).write(to: output.deletingLastPathComponent().appendingPathComponent("ready.json"))
            if !(await waitFor {
                let rows = EventStore.shared.snapshot()
                return rows.contains { $0["name"] as? String == UIApplication.didEnterBackgroundNotification.rawValue }
                    && rows.contains { $0["name"] as? String == UIApplication.willEnterForegroundNotification.rawValue }
            }) { failures.append("real background/foreground notifications missing") }
            try? await Task.sleep(nanoseconds: 500_000_000)
            marker("AfterForeground")
            if !(await waitFor { EventStore.shared.snapshot().filter { ["action", "resource"].contains($0["type"] as? String ?? "") }.count >= 4 }) { failures.append("resumed markers missing") }
            result["events"] = EventStore.shared.snapshot()
        }
'''
    return text[:begin] + replacement + text[end:]


def prepare(attempt, manifest):
    for arm in run.REVISIONS:
        directory = attempt / arm
        source = directory / 'LifecycleSources'
        source.mkdir(exist_ok=True)
        for file in (run.HERE / 'Fixture').iterdir():
            shutil.copyfile(file, source / file.name)
        (source / 'App.swift').write_text(app_variant((run.HERE / 'Fixture/App.swift').read_text()))
        spec = json.loads((directory / 'project.json').read_text())
        target = json.loads(json.dumps(spec['targets']['FixtureLegacy']))
        target['sources'] = ['LifecycleSources']
        target['settings']['base']['SWIFT_OBJC_BRIDGING_HEADER'] = 'LifecycleSources/AllocationCounter.h'
        target['settings']['base']['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.datadoghq.exp160.' + arm + '.legacylifecycle'
        spec['targets']['FixtureLegacyLifecycle'] = target
        spec['schemes']['EXP160Lifecycle'] = {'build': {'targets': {'FixtureLegacyLifecycle': 'all'}}}
        (directory / 'project.json').write_text(json.dumps(spec, indent=2))
        run.call(['xcodegen', 'generate', '--spec', 'project.json'], cwd=directory, log=directory / 'generate-lifecycle.log')
        command = ['xcodebuild', 'build', '-project', str(directory / 'EXP160.xcodeproj'), '-scheme', 'EXP160Lifecycle', '-configuration', 'Release', '-destination', 'generic/platform=iOS Simulator', '-derivedDataPath', str(directory / 'derived'), 'CODE_SIGNING_ALLOWED=NO']
        manifest['commands'].append(command)
        run.call(command, log=directory / 'build-lifecycle.log')
        app = directory / 'derived/Build/Products/Release-iphonesimulator/FixtureLegacyLifecycle.app'
        binary = app / 'FixtureLegacyLifecycle'
        manifest['builds'][arm]['LegacyLifecycle'] = {'app': str(app), 'sha256': run.digest(binary), 'uuid': run.call(['dwarfdump', '--uuid', str(binary)]).strip(), 'deployment_target': '15.0', 'fixture': run.fingerprint(source)}
        run.save(attempt, manifest)


def run_matrix(attempt, manifest):
    for mode in ['lifecycle-automatic', 'lifecycle-manual']:
        for arm in run.REVISIONS:
            def drive(container, destination, bundle):
                ready = container / 'Documents/ready.json'
                deadline = time.monotonic() + 15
                while not ready.exists() and time.monotonic() < deadline:
                    time.sleep(.1)
                if not ready.exists():
                    raise RuntimeError('Lifecycle fixture did not reach exact Home readiness')
                run.call(['xcrun', 'simctl', 'launch', destination, 'com.apple.Preferences'])
                time.sleep(1)
                run.call(['xcrun', 'simctl', 'launch', destination, bundle])
            run.run_one(attempt, manifest, arm, 'LegacyLifecycle', '26.5', mode, 'OS-background-foreground', driver=drive)


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

#!/usr/bin/env python3
"""Bind the unchanged finite input sequence to one reviewed SwiftUI Duo arm."""
import argparse
import json
from pathlib import Path
import sys
import time

import swiftui_duo_runtime as runtime
import capture_sequence as sequence
from capture_io import atomic, encoded


def start(root, framework):
    require = runtime.require; shared = runtime.shared
    require(framework == 'SwiftUI', 'undeclared input framework')
    plan, _ = runtime.reviewed(root); cell, folder = sequence.locations(root, framework)
    summary = shared.read(cell/'summary.json'); identity = summary['identity']; product = plan['product']
    require(summary['state'] == 'RUNNING' and summary['cleanup'] == 'NOT_STARTED'
            and time.time() < summary['native_deadline'], 'native cell cannot admit input')
    require(identity['bundle'] == product['bundle'] and identity['source'] == plan['source']
            and identity['fixture'] == plan['fixture'] and identity['framework'] == framework
            and identity['tracking'] == plan['tracking'] and identity['layout'] == 'stack'
            and type(identity.get('pid')) is int and identity['pid'] > 0, 'foreign native cell identity')
    session_path = folder.parent/'start.json'; session = runtime.q.tool_value(shared.read(session_path)['actual_return'])
    require(session['deviceUUID'] == plan['device']['udid'] and session['deviceIsSimulator'] is True
            and shared.read(folder.parent/'qualified.json')['state'] == 'PASS', 'unqualified input session')
    process = runtime.driver.process_identity(identity['pid'])
    require(process == summary['process_identity'] and process is not None, 'native process absent or replaced')
    folder.mkdir(); (folder/'exchanges').mkdir(); (folder/'received').mkdir()
    binding = dict(root=str(root.resolve()), framework=framework, identity=identity,
        device=plan['device']['udid'], process_identity=process, session_key=session['interactionSessionKey'],
        session_sha256=shared.sha(session_path), plan_sha256=shared.sha(root/'plan.json'),
        native_deadline=summary['native_deadline'], cleanup_deadline=summary['cleanup_deadline'], phase_count=len(sequence.PHASES))
    atomic(folder/'binding.json', encoded(binding))
    return dict(state='BOUND', binding_sha256=shared.sha(folder/'binding.json'), **binding)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('stage', choices=['bind', 'next', 'record', 'stop'])
    parser.add_argument('--root', type=Path, required=True); parser.add_argument('--framework', choices=['SwiftUI'], required=True)
    args = parser.parse_args(); payload = json.load(sys.stdin); root = args.root.resolve(strict=True)
    if args.stage == 'bind': result = start(root, args.framework)
    else: result = getattr(sequence, {'next': 'next_request'}.get(args.stage, args.stage))(root, args.framework, payload)
    print(json.dumps(result), flush=True)

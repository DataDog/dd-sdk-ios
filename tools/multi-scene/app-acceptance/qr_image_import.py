"""Import one newly saved screenshot during the current F08 QR sign-in prompt."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import time

MAX_BYTES = 25 * 1024 * 1024
SUFFIXES = {'.png', '.jpg', '.jpeg', '.heic', '.tiff'}


def require(value, message):
    if not value:
        raise ValueError(message)


def read(path):
    return json.loads(Path(path).read_text())


def save(path, value):
    with Path(path).open('x') as output:
        json.dump(value, output, indent=2)
        output.write('\n')


def inventory(directory):
    result = {}
    for path in Path(directory).iterdir():
        if path.suffix.lower() not in SUFFIXES:
            continue
        try:
            info = path.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISREG(info.st_mode):
            result[path.name] = (info.st_ino, info.st_size, info.st_mtime_ns)
    return result


def candidate(before, current, armed_ns, now_ns):
    fresh = [(name, info) for name, info in current.items()
             if name not in before and armed_ns <= info[2] <= now_ns and 0 < info[1] <= MAX_BYTES]
    require(len(fresh) <= 1, 'More than one new image; no automatic selection')
    return fresh[0] if fresh else None


def live_prompt(root, arm, device, generation=None):
    state = read(root / 'operator/state.json')
    require(state.get('ready') is True and state.get('cleanup_started') is False
            and state.get('context') == 'F08 / ' + arm and state.get('deadline', 0) > time.time() + 10,
            'QR import requires the live authentication prompt')
    require(generation is None or state['generation'] == generation, 'Authentication prompt changed')
    image = Path(state['image_path'])
    require(image.resolve().is_relative_to((root / 'cells' / arm).resolve()), 'Foreign prompt image')
    prompt = read(image.parent / 'prompt.json')['prompt']
    require(prompt['phase'] == 'service-list' and prompt['device'] == device
            and prompt['deadline'] == state['deadline'] and prompt['instruction'] == state['instruction'],
            'Wrong authentication prompt or device')
    return state


def bounded_copy(source, destination, expected):
    descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        require(stat.S_ISREG(before.st_mode)
                and (before.st_ino, before.st_size, before.st_mtime_ns) == expected, 'Screenshot changed')
        with os.fdopen(descriptor, 'rb', closefd=False) as stream:
            data = stream.read(MAX_BYTES + 1)
        after = os.fstat(descriptor)
        require(0 < len(data) == before.st_size <= MAX_BYTES
                and (after.st_ino, after.st_size, after.st_mtime_ns) == expected, 'Screenshot changed while reading')
        with destination.open('xb') as output:
            os.chmod(destination, 0o600)
            output.write(data)
        return hashlib.sha256(data).hexdigest()
    finally:
        os.close(descriptor)


def run(args):
    root = args.root.resolve(strict=True)
    directory = args.directory.resolve(strict=True)
    plan = read(root / 'plan.json')
    require(plan['mode'] == 'smoke' and plan['definition']['gate'] == 'S2:F08', 'Wrong journey plan')
    state = live_prompt(root, args.arm, args.device)
    devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '-j'], timeout=10))
    require(any(d['udid'] == args.device and d['state'] == 'Booted' and d.get('isAvailable')
                for group in devices['devices'].values() for d in group), 'Selected simulator is not booted')
    output = root / ('qr-import-' + args.arm)
    output.mkdir(mode=0o700)
    before = inventory(directory)
    armed_ns = time.time_ns()
    end = time.monotonic() + min(300, state['deadline'] - time.time() - 10)
    save(output / 'armed.json', dict(state='ARMED', at=time.time(), directory=str(directory), device=args.device,
         generation=state['generation'], deadline=state['deadline'], helper_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
         plan_sha256=hashlib.sha256((root / 'plan.json').read_bytes()).hexdigest()))
    print('ARMED: take one fresh QR screenshot; import requires no chat reply.', flush=True)
    previous = None
    copied = None
    result = dict(state='STOPPED_WITHOUT_IMPORT', import_attempts=0)
    try:
        while time.monotonic() < end:
            live_prompt(root, args.arm, args.device, state['generation'])
            selected = candidate(before, inventory(directory), armed_ns, time.time_ns())
            if selected is not None and selected == previous:
                name, info = selected
                require(time.time_ns() - info[2] < 10_000_000_000, 'Screenshot is already stale')
                copied = output / ('input' + Path(name).suffix.lower())
                digest = bounded_copy(directory / name, copied, info)
                live_prompt(root, args.arm, args.device, state['generation'])
                result.update(state='IMPORT_OUTCOME_UNCERTAIN', import_attempts=1, source_sha256=digest,
                              saved_at_ns=info[2], started_at=time.time())
                completed = subprocess.run(['xcrun', 'simctl', 'addmedia', args.device, str(copied)],
                                           capture_output=True, timeout=8)
                result.update(returncode=completed.returncode, finished_at=time.time())
                require(completed.returncode == 0, 'Simulator import failed; no automatic retry')
                result['state'] = 'IMPORTED_NOT_AUTHENTICATED'
                print('IMPORTED: choose the newest image in the app now.', flush=True)
                return
            previous = selected
            time.sleep(.1)
        raise ValueError('No new screenshot in the bounded authentication wait')
    except Exception as error:
        result['reason'] = type(error).__name__ + ': ' + str(error)
        raise
    finally:
        if copied is not None:
            copied.unlink(missing_ok=True)
        save(output / 'result.json', result)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--arm', choices=['baseline', 'candidate'], required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--directory', type=Path, required=True)
    run(parser.parse_args())

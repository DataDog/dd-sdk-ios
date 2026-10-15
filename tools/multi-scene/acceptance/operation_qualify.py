"""One physical capture/transfer qualification; never launches the installed app.

The result admits only the CLI adapters. Startup, native challenges, input,
concurrent topology, SDK ownership and backend acceptance remain separate.
"""
from pathlib import Path
import struct
import time
from urllib.parse import unquote, urlparse
import uuid

import operation_cleanup as cleanup
import operation_display as pixels
import operation_launch as launch
import operation_media as media
import operation_setup as setup
import operation_transport as t


def screenshot(raw, path, device):
    data = setup.read(path, 32 * 1024 * 1024)
    t.require(len(data) >= 33 and data[:8] == b'\x89PNG\r\n\x1a\n'
              and data[12:16] == b'IHDR', 'invalid captured PNG')
    size = list(struct.unpack('>II', data[16:24])); result = raw['result']
    t.require(all(v > 0 for v in size) and size == [result['width'], result['height']]
              and result['imageFormat'] == 'png' and result['deviceIdentifier'] == device
              and Path(unquote(urlparse(result['destination']).path)) == path,
              'screenshot response differs from captured bytes')
    return size


class Qualification:
    """At most one recording/install/push/pull; all outcomes retain raw receipts."""
    def __init__(self, plan_path, admission_path, root, remote, *, environment):
        self.plan_path, self.admission_path = Path(plan_path), Path(admission_path)
        self.plan_raw, self.admission_raw = setup.read(plan_path), setup.read(admission_path)
        self.plan, self.admission = t.load(self.plan_raw), t.load(self.admission_raw)
        self.folder = Path(root); self.folder.mkdir()
        self.remote, self.environment = remote, dict(environment)
        t.require(remote.sequence == 0 and remote.groups == [] and not any(remote.output.iterdir()),
                  'qualification requires a fresh command evidence directory')
        self.started = time.time(); a = self.admission
        t.require(a['state'] == 'NATIVE_ADMITTED' and a['scope'] == 'H06_ADAPTER_QUALIFICATION'
                  and a['reviewer'] == launch.REVIEWER and a['planSHA256'] == t.sha(self.plan_raw),
                  'adapter qualification not separately admitted')
        self.cutoffs = launch.stage_cutoffs(a['cutoffs'], self.started)
        t.require(self.started < a['cutoffs']['launchUntil'] and a['issuedAt'] <= self.started
                  and self.cutoffs['deadline'] - a['issuedAt'] <= 900,
                  'qualification admission expired or unbounded')
        self.nonce = a['nonce']
        t.require(isinstance(self.nonce, str) and str(uuid.UUID(self.nonce)) == self.nonce,
                  'fresh transfer nonce required')
        self.movie = None; self.used = False; self.installed = False; self.absent = False
        self.native_error = None; self.cleanup_error = None; self.cleanup_state = 'UNTOUCHED'
        self.observed = cleanup.ObservedDevice(remote, self.folder, self.cutoffs['launchUntil'], self.started)
        for name, raw in [('plan.json', self.plan_raw), ('admission.json', self.admission_raw)]:
            t.save(self.folder/name, raw)

    def live(self):
        t.require(time.time() < self.observed.deadline and self.remote.identifier == self.plan['device']
                  and setup.read(self.plan_path) == self.plan_raw
                  and setup.read(self.admission_path) == self.admission_raw
                  and t.encode(self.plan) == t.encode(t.load(self.plan_raw))
                  and t.encode(self.admission) == t.encode(t.load(self.admission_raw)),
                  'qualification identity changed or cutoff expired')

    def no_process(self, label):
        raw, _ = self.observed.command(['device', 'info', 'processes'], label)
        launch.require_no_task_process(raw['result'].get('runningProcesses'), self.app, self.plan['product'])

    def apps(self, label):
        raw, _ = self.observed.command(['device', 'info', 'apps', '--bundle-id', launch.BUNDLE], label)
        value = raw['result']
        t.require(value.get('deviceIdentifier') == self.remote.identifier
                  and value.get('matchingBundleIdentifier') == launch.BUNDLE
                  and isinstance(value.get('apps'), list), 'ambiguous task installation inventory')
        return value['apps']

    def preflight(self):
        self.live(); self.app = launch.product(self.plan)
        self.toolchain = launch.toolchain(self.plan, self.environment)
        setup.command(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(self.app)],
                      self.folder, 'signature', self.cutoffs['launchUntil'])
        raw, _ = self.observed.command(['device', 'info', 'details'], 'device')
        h, p = raw['result']['hardwareProperties'], raw['result']['deviceProperties']
        t.require(h['reality'] == 'physical' and h['deviceType'] == 'iPad' and h['udid'] == self.plan['udid']
                  and p['developerModeStatus'] == 'enabled' and p['ddiServicesAvailable'] is True,
                  'physical iPad unavailable')
        self.hardware = dict(udid=h['udid'], os=p['osVersionNumber'], build=p['osBuildUpdate'])
        raw, _ = self.observed.command(['device', 'info', 'lockState'], 'lock')
        t.require(raw['result']['passcodeRequired'] is False and raw['result']['unlockedSinceBoot'] is True,
                  'physical iPad locked')
        raw, _ = self.observed.command(['device', 'info', 'displays'], 'display')
        self.display = setup.display(raw)
        t.require(self.apps('initial-apps') == [], 'task app already installed')
        self.no_process('initial-processes'); self.absent = True

    def decode(self, source, kind):
        self.live(); decoder = self.plan['decoder']
        proof = pixels.decode(decoder['binary']['path'], decoder['binary']['sha256'], kind,
            source, self.folder/('decode-' + kind.lower()), min(180, self.observed.deadline-time.time()),
            source_sha256=decoder['source']['sha256'])
        frames = pixels.checked(proof, kind)
        t.require(frames and all([row['width'], row['height']] == self.size for row in frames),
                  'decoded capture dimensions differ from screenshot')
        return proof

    def exercise(self):
        self.live(); launch.product(self.plan)
        bounded = media.ExecutionDevice(self.remote, execution_until=self.cutoffs['executionUntil'],
                                        deadline=self.cutoffs['deadline'])
        self.observed = cleanup.ObservedDevice(self.remote, self.folder, self.cutoffs['recordUntil'], self.started)
        self.installed = True  # An attempted install may leave a bundle even when its receipt fails.
        self.observed.command(['device', 'install', 'app', str(self.app)], 'install')
        self.no_process('installed-processes')
        self.movie = media.Movie(bounded, self.folder/'movie', record_until=self.cutoffs['recordUntil'],
                                stop_until=self.cutoffs['stopUntil'], environment=self.environment)
        self.movie.start()
        payload = t.encode(dict(kind='H06_ADAPTER_OPAQUE_PAYLOAD', nonce=self.nonce))
        source, destination = self.folder/'payload.json', self.folder/'returned.json'
        t.save(source, payload)
        # Container-root file needs no app launch or assumed Documents directory.
        remote_path = 'h06-adapter-' + self.nonce + '.json'
        raw, receipt = self.observed.push(launch.BUNDLE, source, remote_path, 'push', self.observed.deadline)
        t.transferred(raw, receipt, device=self.remote.identifier, bundle=launch.BUNDLE,
                      source=source, destination=remote_path, deadline=self.observed.deadline, optional=False)
        raw, receipt = self.observed.pull(launch.BUNDLE, remote_path, destination, 'pull', self.observed.deadline)
        t.require(t.transferred(raw, receipt, device=self.remote.identifier, bundle=launch.BUNDLE,
                  source=remote_path, destination=destination, deadline=self.observed.deadline, optional=True)
                  and setup.read(destination) == payload and setup.read(source) == payload,
                  'transfer payload absent, substituted or changed')
        self.movie.running()
        image = self.folder/'screen.png'
        raw, _ = self.observed.command(['device', 'capture', 'screenshot', '--destination', str(image)], 'screenshot')
        self.size = screenshot(raw, image, self.remote.identifier)
        self.movie.running(); movie = self.movie.finish(accept=True)
        self.observed = cleanup.ObservedDevice(self.remote, self.folder, self.cutoffs['executionUntil'], self.started)
        self.capture = dict(image=self.decode(image, 'IMAGE'), movie=self.decode(movie, 'MOVIE'),
                            payload=pixels.reference(destination), display=self.display)
        self.live(); launch.product(self.plan)

    def teardown(self):
        # No input or app launch is ever issued. A discovered task process blocks
        # removal instead of manufacturing a human release acknowledgement.
        if self.movie is not None and self.movie.process is not None and not self.movie.reaped:
            if (self.movie.folder/'process-finished.json').exists():
                raise ValueError('recorder already stopped without proven quiescence')
            self.movie.finish(accept=False)
        t.require(self.movie is None or self.movie.process is None or self.movie.reaped,
                  'recorder not reaped; task app preserved')
        self.remote.quiescent(self.cutoffs['deadline'])
        if not self.installed: return
        t.require(self.absent, 'original task absence unproved')
        self.observed = cleanup.ObservedDevice(self.remote, self.folder, self.cutoffs['deadline'], self.started)
        self.live(); self.no_process('cleanup-processes')
        if self.apps('cleanup-apps'):
            self.observed.command(['device', 'uninstall', 'app', launch.BUNDLE], 'uninstall')
        t.require(self.apps('final-apps') == [], 'task app remains')
        self.no_process('final-processes')
        # Each command receipt proves its own group absent; also retain one final
        # whole-owned-group inventory without overwriting the pre-teardown proof.
        remaining = {group: media.group_members(group, self.cutoffs['deadline']) for group in self.remote.groups}
        t.save(self.folder/'final-workers.json', t.encode(dict(groups=remaining, at=time.time())))
        t.require(not any(remaining.values()) and time.time() < self.cutoffs['deadline'], 'final workers remain')
        self.cleanup_state = 'PASS'

    def run(self):
        t.require(not self.used, 'qualification already consumed'); self.used = True
        t.save(self.admission_path.with_suffix('.consumed.json'),
               t.encode(dict(root=str(self.folder.resolve()), admissionSHA256=t.sha(self.admission_raw), at=time.time())))
        try:
            self.preflight(); self.exercise()
        except BaseException as error:
            self.native_error = dict(type=type(error).__name__, reason=str(error))
        finally:
            try: self.teardown()
            except BaseException as error:
                self.cleanup_error = dict(type=type(error).__name__, reason=str(error)); self.cleanup_state = 'BLOCKED'
        passed = self.native_error is None and self.cleanup_state == 'PASS'
        value = dict(state='PHYSICAL_ADAPTER_QUALIFIED' if passed else 'INVALID', device=self.remote.identifier,
            helpers=self.plan['helpers'], planSHA256=t.sha(self.plan_raw), admissionSHA256=t.sha(self.admission_raw),
            capture=getattr(self, 'capture', None), hardware=getattr(self, 'hardware', None),
            toolchain=getattr(self, 'toolchain', None),
            error=self.native_error, cleanup=self.cleanup_state, cleanupError=self.cleanup_error,
            installAttempted=self.installed, nativeLaunches=0, inputActions=0, releaseAcceptance=False, gatesClosed=[],
            containerAbsence='UNVERIFIED', cleanupScope='OS_APP_UNINSTALL_CONTRACT' if self.cleanup_state == 'PASS' else None,
            limits='CLI capture and app-container transfer only; no startup, topology, input, SDK or backend evidence.',
            finishedAt=time.time())
        t.save(self.folder/'verdict.json', t.encode(value))
        return value


def main():
    import argparse
    import sys
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', required=True)
    parser.add_argument('--admission', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'interactive-transitions'))
    import physical_io
    root = Path(args.output).resolve(); root.mkdir()
    plan = t.load(setup.read(args.plan))
    remote = physical_io.Device(plan['device'], root/'device')
    result = Qualification(args.plan, args.admission, root/'qualification', remote,
                           environment=physical_io.shared.environment()).run()
    print(result['state'])
    return 0 if result['state'] == 'PHYSICAL_ADAPTER_QUALIFIED' else 1


if __name__ == '__main__':
    raise SystemExit(main())

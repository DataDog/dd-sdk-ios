"""H06 cleanup after real release; never changes scenario/evidence verdicts.

The original channel cutoff bounds this entire operation. Native driver/pump stop,
input idle and exact process identity precede task-only removal. No caller-provided
PASS or elapsed timeout can replace these observations.
"""
import base64
from pathlib import Path
import time
import uuid

import operation_setup as setup
import operation_transport as t


def pending_response(raw, *, context_raw, native_local_raw, **arguments):
    """Recognize one async driver wait, without inventing a stopped receipt."""
    t.context_response(context_raw, **arguments)
    identity, deadline = arguments['identity'], arguments['deadline']
    capture, _ = t.response(arguments['reply_raw'], arguments['request_raw'], arguments['input_raw'], identity)
    value = t.load(raw)
    fields = {'schemaVersion', 'identity', 'requestSHA256', 'replySHA256', 'captureSHA256',
              'contextCompletionSHA256', 'driver', 'state', 'pumpStopped', 'deadline', 'finishedAt'}
    t.require(set(value) in [fields, fields | {'nativeLocalResultSHA256'}]
              and type(value['schemaVersion']) is int and value['schemaVersion'] == 1
              and value['identity'] == identity and value['state'] == 'NOT_STOPPED'
              and value['pumpStopped'] is False, 'not a pending cleanup receipt')
    t.require(t.load(arguments['input_raw'])['phase'] == 'cleanup', 'not a cleanup request')
    for key, observed in [('requestSHA256', arguments['request_raw']), ('replySHA256', arguments['reply_raw']),
                          ('captureSHA256', capture), ('contextCompletionSHA256', arguments['completion_raw'])]:
        t.require(value[key] == t.sha(observed), 'pending cleanup bytes differ')
    driver = value['driver']
    t.require(isinstance(driver, dict) and set(driver) in [{'requested', 'stopped'},
              {'requested', 'stopped', 'terminalBeforeStop'}] and driver['requested'] is True
              and driver['stopped'] is False, 'pending driver identity missing')
    if 'terminalBeforeStop' in driver:
        terminal = driver['terminalBeforeStop']
        t.require(isinstance(terminal, dict) and type(terminal.get('schemaVersion')) is int
                  and terminal['schemaVersion'] == 1 and terminal.get('scenarioID') == identity['setupProfile']['scenario'],
                  'foreign pending terminal')
    t.require(value.get('nativeLocalResultSHA256') == (t.sha(native_local_raw) if native_local_raw is not None else None),
              'pending native result differs')
    t.require(setup.finite(value['deadline']) and value['deadline'] == deadline
              and setup.finite(value['finishedAt'])
              and t.load(arguments['completion_raw'])['finishedAt'] <= value['finishedAt'] < deadline,
              'pending cleanup late or reordered')
    return dict(state='CLEANUP_PENDING', receiptSHA256=t.sha(raw), teardownAuthorized=False)


class ObservedDevice:
    """Check actual returned observations against their own durable IO receipts."""
    def __init__(self, remote, folder, deadline, released_at):
        self.remote, self.folder, self.deadline, self.released_at = remote, folder, deadline, released_at
        self.identifier = remote.identifier

    def live(self):
        t.require(time.time() < self.deadline and self.remote.identifier == self.identifier,
                  'cleanup adapter expired or device changed')

    def verify(self, result, receipt, label):
        self.live()
        source = self.remote.output / (f'{self.remote.sequence:05d}-' + label)
        raw, recorded = setup.read(source / 'response.json'), setup.read(source / 'receipt.json')
        prefix = f'{self.remote.sequence:05d}-' + label
        t.save(self.folder / (prefix + '-response.json'), raw)
        t.save(self.folder / (prefix + '-receipt.json'), recorded)
        t.require(t.load(raw) == result and t.load(recorded) == receipt
                  and receipt['response_sha256'] == t.sha(raw), 'returned cleanup observation was substituted')
        t.require(receipt['before'] == receipt['remaining'] == [] and receipt.get('quiescence_error') is None
                  and type(receipt['returncode']) is int
                  and all(setup.finite(receipt.get(k)) for k in ['started_at', 'finished_at', 'deadline'])
                  and self.released_at <= receipt['started_at'] <= receipt['finished_at']
                  < min(receipt['deadline'], self.deadline), 'cleanup command late or unreaped')
        return result, receipt

    def push(self, bundle, source, destination, label, deadline):
        self.live()
        t.require(deadline == self.deadline, 'cleanup transfer deadline changed')
        return self.verify(*self.remote.push(bundle, source, destination, label, deadline), label)

    def pull(self, bundle, source, destination, label, deadline, **kwargs):
        self.live()
        t.require(deadline == self.deadline, 'cleanup transfer deadline changed')
        return self.verify(*self.remote.pull(bundle, source, destination, label, deadline, **kwargs), label)

    def command(self, args, label, *, check=True):
        self.live()
        value, receipt = self.verify(*self.remote.command(args, label, self.deadline, check=check), label)
        info = value.get('info', {}); actual = list(info.get('arguments', []))
        t.require(info.get('commandType') == 'devicectl.' + '.'.join(args[:3]), 'foreign cleanup command')
        if actual and actual[0] == 'devicectl': actual.pop(0)
        for flag in ['--device', '--timeout', '--json-output']:
            count = actual.count(flag)
            t.require(count == 1 if flag == '--device' else count <= 1, 'ambiguous cleanup option')
            if count:
                index = actual.index(flag); t.require(index + 1 < len(actual), 'missing cleanup option value')
                if flag == '--device': t.require(actual[index + 1] == self.identifier, 'foreign cleanup device')
                del actual[index:index + 2]
        t.require(actual == args, 'cleanup command arguments differ')
        if check:
            t.require(receipt['returncode'] == 0 and info.get('outcome') == 'success', 'cleanup command failed')
        return value, receipt


class Cleanup:
    """One release, at most two stop captures, then one task-only teardown."""
    def __init__(self, host, *, original_native_raw, original_terminal, wait=lambda: time.sleep(.25)):
        self.host, self.remote = host, host.remote
        self.identity = t.load(t.encode(host.identity)); self.expected = t.load(t.encode(host.expected))
        self.deadline = host.channel.deadline; self.bundle = host.channel.bundle
        self.folder = host.channel.output / 'host-cleanup'; self.folder.mkdir()
        self.wait = wait; self.used = False; self.failed = False; self.removal_used = False
        t.require(original_native_raw is None or isinstance(original_native_raw, bytes), 'native expectation must be bytes or explicit absence')
        t.require(original_terminal is None or isinstance(original_terminal, dict), 'terminal expectation must be an object or explicit absence')
        self.original_native_raw = original_native_raw
        self.original_terminal = t.load(t.encode(original_terminal)) if original_terminal is not None else None
        self.live()
        t.require(host.channel.remote is self.remote and self.remote.identifier == self.expected['device'],
                  'cleanup remote differs from original host')
        product = setup.installed_code.validate(t.load(host.installed_raw), host.app, self.identity['runID'],
            self.identity['profile']['sourceRevision'], self.identity['processID'])
        t.require(all(product[k] == self.expected['product'][k] for k in ['bundleIdentifier', 'executable', 'binaries'])
                  and product['bundleIdentifier'] == self.bundle, 'cleanup product differs')
        self.product = product
        reference = setup.read(host.folder / 'process-before-response.json')
        source = t.load(reference); args = source['info']['arguments']
        t.require(source['info']['commandType'] == 'devicectl.device.info.processes'
                  and source['info']['outcome'] == 'success' and args.count('--device') == 1
                  and args[args.index('--device') + 1] == self.remote.identifier, 'original process observation missing')
        self.process = setup.device_process(source, self.identity, self.product, host.app.name)
        t.save(self.folder / 'original-process.json', reference)
        if original_native_raw is not None: t.save(self.folder / 'original-native-result.json', original_native_raw)
        if original_terminal is not None: t.save(self.folder / 'original-terminal.json', t.encode(original_terminal))
        request = dict(kind='HUMAN_RELEASE_REQUIRED', request_id=str(uuid.uuid4()), run_id=self.identity['runID'],
            channel_identity_sha256=t.sha(t.encode(self.identity)), phase='operations.cleanup', issued_at=time.time(),
            deadline=self.deadline, instruction='Release all input and confirm Released. Leave both task windows visible; '
                'the runner will verify idle and remove only the test app.')
        self.request_raw = t.encode(request); t.save(self.folder / 'release-request.json', self.request_raw)
        t.save(self.folder / 'definition.json', t.encode(dict(identity=self.identity, deadline=self.deadline,
            bundle=self.bundle, device=self.remote.identifier, maximumStopCaptures=2,
            originalProcessSHA256=t.sha(reference),
            originalNativeResult=dict(present=original_native_raw is not None,
                sha256=t.sha(original_native_raw) if original_native_raw is not None else None),
            originalTerminal=dict(present=original_terminal is not None,
                sha256=t.sha(t.encode(original_terminal)) if original_terminal is not None else None),
            teardownAuthorized=False)))

    def live(self):
        t.require(time.time() < self.deadline, 'original cleanup cutoff expired')
        t.require(self.host.channel.deadline == self.deadline and self.host.channel.bundle == self.bundle
                  and t.encode(self.host.identity) == t.encode(self.identity)
                  and t.encode(self.host.channel.identity) == t.encode(self.identity)
                  and self.remote.identifier == self.expected['device'], 'cleanup identity or deadline changed')

    def fail(self, stage, error):
        self.failed = True
        t.save(self.folder / (stage + '-failure.json'), t.encode(dict(state='INVALID', stage=stage,
            errorType=type(error).__name__, reason=str(error), deadline=self.deadline,
            finishedAt=time.time(), teardownAuthorized=False, scenario='UNCHANGED', evidence='UNCHANGED')))

    def current_process(self, label):
        self.live(); raw, _ = self.observed.command(['device', 'info', 'processes'], label)
        current = setup.device_process(raw, self.identity, self.product, self.host.app.name)
        t.require(current == self.process, 'original device process replaced')
        self.live(); return current

    def download(self, source, destination, label):
        self.live()
        return self.channel.transfer(self.observed.pull, source, destination, label, optional=True)

    def stop_capture(self, attempt):
        capture = self.channel.capture('cleanup', with_context=True)
        source = self.channel.output / f'{self.channel.sequence:04d}-cleanup'
        request, inner = setup.read(source / 'request.json'), setup.read(source / 'input-request.json')
        transport = t.load(setup.read(source / 'transport-result.json'))
        replies = [setup.read(p) for p in source.glob('response-*.json')]
        replies = [raw for raw in replies if t.sha(raw) == transport['response_sha256']]
        t.require(len(replies) == 1, 'successful cleanup reply ambiguous')
        fingerprint = t.sha(request); prefix = 'Documents/' + self.identity['runID'] + '.operations-'
        for poll in range(1, 100_001):
            destination = source / f'driver-{poll:06d}.json'
            if self.download(prefix + 'cleanup-' + fingerprint + '-driver.json', destination, 'cleanup-driver'):
                raw = setup.read(destination); break
            self.wait()
        else: raise ValueError('cleanup sidecar attempt bound exhausted')
        native = source / 'native-local-result.json'
        native_raw = setup.read(native) if self.download(prefix + 'native-local-result.json', native, 'cleanup-native-result') else None
        t.require(native_raw == self.original_native_raw, 'original native result changed or unexpected')
        arguments = dict(context_raw=setup.read(source / 'context.json'),
            completion_raw=setup.read(source / 'context-result.json'), reply_raw=replies[0], request_raw=request,
            input_raw=inner, identity=self.identity, deadline=self.deadline, native_local_raw=native_raw)
        receipt = t.load(raw)
        if receipt.get('state') == 'NOT_STOPPED':
            result = pending_response(raw, **arguments)
        else:
            result = t.cleanup_response(raw, **arguments)
        t.require(receipt['driver'].get('terminalBeforeStop') == self.original_terminal,
                  'original terminal changed or unexpected')
        t.save(source / 'stop-joined.json', t.encode(result))
        self.live()
        if result['state'] == 'CLEANUP_PENDING': return None
        t.require(setup.read(source / 'capture.json') == t.response(replies[0], request, inner, self.identity)[0],
                  'cleanup capture changed')
        owners = setup.visible_owners(capture)
        _, context = t.context_response(arguments['context_raw'], **{k:v for k,v in arguments.items()
            if k not in {'context_raw', 'native_local_raw'}})
        for key in ['sdkBefore', 'sdkAfter']:
            sample = context[key]
            t.require(sample.get('failure') is None and sample['before'] == sample['after'] == capture['after'],
                      'input changed during cleanup context capture')
        before_setup = self.host.folder / 'native-capture.json'
        if before_setup.exists():
            t.require(owners == setup.visible_owners(t.load(setup.read(before_setup))), 'cleanup owners were replaced')
        return dict(state='STOPPED_AND_IDLE', captureSHA256=t.sha(setup.read(source / 'capture.json')),
            receiptSHA256=t.sha(raw), requestSHA256=fingerprint, attempt=attempt)

    def run(self, acknowledgement_raw):
        # No caller/backend work can be inserted between the final idle capture
        # and removal. The helpers below remain private fixture control points.
        self._collect(acknowledgement_raw)
        return self._remove()

    def _collect(self, acknowledgement_raw):
        t.require(not self.used, 'cleanup release already consumed'); self.used = True
        try:
            self.live(); t.save(self.folder / 'release-ack.json', acknowledgement_raw)
            acknowledgement = t.load(acknowledgement_raw); request = t.load(self.request_raw)
            setup.release.validate_ack(request, self.request_raw, acknowledgement, time.time())
            t.require(setup.finite(acknowledgement['at']), 'invalid release time')
            t.save(self.folder / 'release-consumed.json', t.encode(dict(requestSHA256=t.sha(self.request_raw), at=time.time())))
            self.observed = ObservedDevice(self.remote, self.folder, self.deadline, acknowledgement['at'])
            # New host output, same frozen native identity/cutoff. Never renew the
            # original channel or reuse its consumed setup request.
            self.channel = t.Channel(self.observed, self.bundle, self.folder / 'channel', self.identity, deadline=self.deadline)
            self.current_process('cleanup-process-before')
            raw, _ = self.observed.command(['device', 'info', 'details'], 'cleanup-device')
            hardware, properties = raw['result']['hardwareProperties'], raw['result']['deviceProperties']
            t.require(hardware['reality'] == 'physical' and hardware['deviceType'] == 'iPad'
                      and hardware['udid'] == self.expected['udid']
                      and all(isinstance(properties.get(k), str) and properties[k].strip()
                              for k in ['osVersionNumber', 'osBuildUpdate']), 'physical cleanup OS identity missing')
            self.device_os = dict(version=properties['osVersionNumber'], build=properties['osBuildUpdate'])
            joined = None
            for attempt in [1, 2]:
                joined = self.stop_capture(attempt)
                if joined is not None: break
                if attempt == 1: self.wait()
            t.require(joined is not None, 'driver still running after bounded cleanup captures')
            self.current_process('cleanup-process-ready')
            self.live()
            artifacts = {str(p.relative_to(self.folder)): setup.file_sha(p)
                         for p in sorted(self.folder.rglob('*')) if p.is_file()}
            result = dict(state='CLEANUP_READY', identity=self.identity, deadline=self.deadline,
                artifacts=artifacts, stopped=joined, releaseSHA256=t.sha(acknowledgement_raw), deviceProcess=self.process,
                finishedAt=time.time(), teardownAuthorized=False, processAbsence='PENDING', appAbsence='PENDING')
            self.ready_raw = t.encode(result); t.save(self.folder / 'ready.json', self.ready_raw)
            return result
        except Exception as error:
            self.fail('capture', error); raise

    def _remove(self):
        t.require(self.used and not self.failed and not self.removal_used and hasattr(self, 'ready_raw'),
                  'cleanup readiness absent, failed or already consumed')
        self.removal_used = True
        try:
            self.live(); t.require(setup.read(self.folder / 'ready.json') == self.ready_raw, 'cleanup readiness changed')
            ready = t.load(self.ready_raw)
            t.require(all(setup.file_sha(self.folder / name) == digest for name, digest in ready['artifacts'].items()),
                      'cleanup evidence changed before removal')
            self.remote.quiescent(self.deadline)
            proof = setup.read(self.remote.output / 'before-cleanup-quiescence.json')
            t.save(self.folder / 'host-quiescence.json', proof); quiet = t.load(proof)
            t.require(quiet['state'] == 'PASS' and quiet['remaining'] == []
                      and quiet['groups'] == self.remote.groups and quiet['deadline'] == self.deadline
                      and setup.finite(quiet['at']) and t.load(self.ready_raw)['finishedAt'] <= quiet['at'] < self.deadline,
                      'host commands not quiescent')
            self.current_process('cleanup-process-final')
            self.live()
            t.save(self.folder / 'teardown-admission.json', t.encode(dict(state='TASK_TEARDOWN_ADMITTED',
                identity=self.identity, process=self.process, bundle=self.bundle, deadline=self.deadline,
                readySHA256=t.sha(self.ready_raw), hostQuiescenceSHA256=t.sha(proof), at=time.time())))
            stopped, _ = self.observed.command(['device', 'process', 'terminate', '--pid', str(self.identity['processID'])], 'cleanup-terminate')
            value = stopped['result']
            t.require(value.get('deviceIdentifier') == self.remote.identifier
                      and value.get('process') == dict(processIdentifier=self.process['processID'], executable=self.process['executable']),
                      'termination affected a different process')
            self.process_absence('cleanup-process-absence')
            removed, _ = self.observed.command(['device', 'uninstall', 'app', self.bundle], 'cleanup-uninstall')
            t.require(removed['result'].get('deviceIdentifier') == self.remote.identifier
                      and removed['result'].get('uninstalledApplications') == [dict(bundleID=self.bundle)], 'uninstall result differs')
            apps, _ = self.observed.command(['device', 'info', 'apps', '--bundle-id', self.bundle], 'cleanup-app-absence')
            value = apps['result']
            t.require(value.get('deviceIdentifier') == self.remote.identifier and value.get('matchingBundleIdentifier') == self.bundle
                      and value.get('apps') == [], 'task app absence unproved')
            self.process_absence('cleanup-process-final-absence')
            # The physical cleanup policy relies on the observed OS uninstall.
            # A failed file-list query cannot prove absence, so do not issue one.
            # This disposition never substitutes for pre-SDK freshness checks.
            self.live()
            bindings = {p.name: setup.file_sha(p) for p in sorted(self.folder.iterdir()) if p.is_file()}
            result = dict(state='TASK_APP_REMOVED', processAbsence='PASS', appAbsence='PASS', containerAbsence='UNVERIFIED',
                dataDisposition='OS_APP_UNINSTALL_CONTRACT', dataScope='PRIVATE_APP_CONTAINER',
                device=self.remote.identifier, deviceOS=self.device_os, bundleIdentifier=self.bundle,
                directlyObservedFilesystemAbsence=False, cleanupEvidence=bindings,
                outOfScope=['Keychain', 'shared containers', 'cloud data', 'unqueried filesystem state'],
                deadline=self.deadline, finishedAt=time.time(), scenario='UNCHANGED', evidence='UNCHANGED',
                preAdmissionFreshness='SEPARATE_PROOF_REQUIRED', releaseAcceptance=False)
            t.save(self.folder / 'result.json', t.encode(result)); return result
        except Exception as error:
            self.fail('removal', error); raise

    def process_absence(self, label):
        self.live(); raw, _ = self.observed.command(['device', 'info', 'processes'], label)
        rows = raw.get('result', {}).get('runningProcesses')
        t.require(isinstance(rows, list) and all(isinstance(row, dict) and type(row.get('processIdentifier')) is int
                  and row['processIdentifier'] > 0 and isinstance(row.get('executable'), str) and row['executable']
                  for row in rows), 'process absence inventory missing')
        t.require(all(row.get('processIdentifier') != self.process['processID'] and row.get('executable') != self.process['executable']
                      for row in rows), 'task process remains or restarted')
        self.live()

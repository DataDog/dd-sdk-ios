"""H06 prompts bound to one channel; no native input, SDK or cleanup authority.

The existing page owns real button acknowledgements. Only its UI phase is mapped:
original operations.setup/cleanup request bytes are never rewritten. A host runner
must still qualify the physical adapter before using these preparation helpers.
"""
import contextlib
import importlib.util
from pathlib import Path
import re
import time

import operation_setup as setup
import operation_transport as t

_spec = importlib.util.spec_from_file_location('operation_human_operator',
    Path(__file__).resolve().parents[1] / 'automatic-coverage/human_operator.py')
page = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(page)

REQUEST_FIELDS = {'kind', 'request_id', 'run_id', 'channel_identity_sha256', 'phase',
                  'issued_at', 'deadline', 'instruction'}
ACK_FIELDS = {'kind', 'request_sha256', 'request_id', 'run_id', 'at', 'user_message'}
WAIT_INSTRUCTION = 'Release recorded. Waiting for native idle evidence; do not interact.'


def clean_path(path):
    path = Path(path)
    t.require(path.is_absolute() and path == path.resolve()
              and not any(p.is_symlink() for p in [path, *path.parents]), 'noncanonical or symlinked operator path')
    return path


def read(path):
    return setup.read(clean_path(path), t.MAX_BYTES)


class Operator:
    """One setup and one cleanup prompt, with one-use acknowledgements.

    Cleanup may supersede setup. A status update cannot consume a pending click;
    neither an acknowledgement nor this adapter may authorize native teardown.
    The original outer budget replaces the unrelated legacy 300-second cutoff.
    """
    def __init__(self, directory, channel, *, server_raw):
        self.directory = clean_path(directory)
        self.channel = channel
        self.output = clean_path(channel.output)
        t.require(self.directory.is_dir() and self.output.is_dir()
                  and self.output.is_relative_to(self.directory.parent / 'cells'), 'operator/cell output not preflighted')
        self.deadline = channel.deadline
        self.identity_raw = t.encode(channel.identity)
        self.identity = t.load(self.identity_raw)
        t.require(self.identity.get('schemaVersion') == 2 and t.identifier(self.identity.get('challengeID')),
                  'physical setup channel required')
        t.validate_setup(self.identity.get('setupProfile'))
        self.server_raw = bytes(server_raw)
        server = t.load(server_raw)
        t.require(set(server) == {'state', 'pid', 'url', 'started_at', 'seconds', 'native_launches', 'directory', 'nonce'}
                  and server['state'] == 'BOUND_OPERATOR_PAGE' and type(server['pid']) is int and server['pid'] > 0
                  and server['directory'] == str(self.directory) and t.identifier(server['nonce'])
                  and type(server['native_launches']) is int and server['native_launches'] == 0
                  and isinstance(server['url'], str) and re.fullmatch(r'http://127\.0\.0\.1:[0-9]{1,5}', server['url'])
                  and 0 < int(server['url'].rsplit(':', 1)[1]) < 65536
                  and type(server['seconds']) is int and 0 < server['seconds'] <= 21600
                  and setup.finite(server['started_at']) and setup.finite(self.deadline)
                  and server['started_at'] <= time.time() < self.deadline <= server['started_at'] + server['seconds'],
                  'foreign or expired operator server binding')
        self.context = 'H06 Operations: ' + self.identity['runID']
        self.binding_raw = t.encode(dict(schemaVersion=1, directory=str(self.directory), output=str(self.output),
            identity=self.identity, device=channel.remote.identifier, bundle=channel.bundle,
            deadline=self.deadline, serverSHA256=t.sha(self.server_raw), releaseAcceptance=False))
        self.pending = None
        self.seen = set()
        self.phases = set()
        self.cleanup_started = False
        self.folder = self.directory / 'operation'
        clean_path(self.directory / '.publication.lock')
        with page.publication_lock(self.directory):
            t.require(read(self.directory / 'server.json') == self.server_raw, 'operator server receipt changed')
            self.state_raw = read(self.directory / 'state.json')
            state = t.load(self.state_raw)
            t.require(state.get('ready') is False and state.get('cleanup_started') is False
                      and state.get('deadline') is None and 'release_request' not in state,
                      'stale operator page before binding')
            self.folder.mkdir()  # Existing bindings cannot be resumed or overwritten.
            t.save(self.folder / 'binding.json', self.binding_raw)
            t.save(self.folder / 'server.json', self.server_raw)
            t.save(self.folder / 'initial-state.json', self.state_raw)

    def live(self):
        clean_path(self.directory / '.publication.lock')
        t.require(time.time() < self.deadline and self.channel.deadline == self.deadline
                  and clean_path(self.channel.output) == self.output
                  and t.encode(self.channel.identity) == self.identity_raw, 'operator channel changed or expired')
        binding = t.load(self.binding_raw)
        t.require(self.channel.bundle == binding['bundle'] and self.channel.remote.identifier == binding['device'],
                  'operator device or bundle changed')
        t.require(read(self.folder / 'binding.json') == self.binding_raw
                  and read(self.directory / 'server.json') == self.server_raw
                  and read(self.folder / 'server.json') == self.server_raw, 'operator binding receipt changed')

    @contextlib.contextmanager
    def locked(self):
        clean_path(self.directory / '.publication.lock')
        with page.publication_lock(self.directory):
            self.live()
            yield

    def verify_pending(self):
        pending = self.pending
        t.require(pending is not None, 'no pending operator request')
        t.require(read(pending['path']) == pending['raw']
                  and read(pending['folder'] / 'request.json') == pending['raw']
                  and read(pending['folder'] / 'routing.json') == pending['routing_raw']
                  and t.sha(read(pending['folder'] / 'page.json')) == t.load(pending['routing_raw'])['pageSHA256'],
                  'pending request or routing changed')
        state_raw = read(self.directory / 'state.json')
        ack_path = pending['path'].with_name('operator-released.json')
        if not ack_path.exists():
            t.require(state_raw == self.state_raw, 'pending readiness was replaced without acknowledgement')
            return None, state_raw
        raw = read(ack_path)
        reply = t.load(raw)
        t.require(set(reply) == ACK_FIELDS and setup.finite(reply['at'])
                  and isinstance(reply['user_message'], str), 'operator acknowledgement shape differs')
        setup.release.validate_ack(pending['request'], pending['raw'], reply, time.time())
        state = t.load(state_raw)
        expected_keys = {'schema_version', 'generation', 'published_at', 'context', 'instruction', 'deadline',
                         'has_image', 'ready', 'cleanup_started'}
        t.require(set(state) == expected_keys and type(state['schema_version']) is int and state['schema_version'] == 1
                  and t.identifier(state['generation']) and state['generation'] != pending['generation']
                  and setup.finite(state['published_at']) and reply['at'] <= state['published_at'] <= time.time()
                  and state['context'] == self.context and state['instruction'] == WAIT_INSTRUCTION
                  and state['deadline'] is None and state['has_image'] is False and state['ready'] is False
                  and state['cleanup_started'] is self.cleanup_started, 'acknowledgement page transition differs')
        return raw, state_raw

    def present(self, request_path):
        path = clean_path(request_path)
        with self.locked():
            raw = read(path)
            request = t.load(raw)
            t.require(set(request) == REQUEST_FIELDS and request['kind'] == 'HUMAN_RELEASE_REQUIRED'
                      and request['phase'] in ['operations.setup', 'operations.cleanup']
                      and t.identifier(request['request_id']) and request['run_id'] == self.identity['runID']
                      and request['channel_identity_sha256'] == t.sha(self.identity_raw)
                      and request['deadline'] == self.deadline and setup.finite(request['issued_at'])
                      and t.load(self.server_raw)['started_at'] <= request['issued_at'] <= time.time() < self.deadline
                      and isinstance(request['instruction'], str) and request['instruction'].strip(),
                      'foreign, stale or invalid release request')
            phase = request['phase']
            cleanup = phase == 'operations.cleanup'
            expected_path = self.output / ('host-cleanup' if cleanup else 'host-setup') / 'release-request.json'
            t.require(path == expected_path and not path.with_name('operator-released.json').exists(),
                      'foreign path or acknowledgement predates publication')
            t.require(phase not in self.phases and request['request_id'] not in self.seen
                      and (cleanup or not self.cleanup_started), 'duplicate request or ordinary input after cleanup')
            previous = self.pending
            previous_ack = None
            if previous:
                t.require(cleanup, 'pending setup cannot be replaced by ordinary input')
                previous_ack, _ = self.verify_pending()
            else:
                t.require(read(self.directory / 'state.json') == self.state_raw, 'unowned operator page generation')
            folder = self.folder / phase
            folder.mkdir()
            t.save(folder / 'request.json', raw)
            t.save(folder / 'intent.json', t.encode(dict(requestPath=str(path), bindingSHA256=t.sha(self.binding_raw),
                requestSHA256=t.sha(raw), phase=phase, deadline=self.deadline, sdkAdmitted=False, teardownAuthorized=False)))
            self.seen.add(request['request_id']); self.phases.add(phase)
            self.cleanup_started = cleanup or self.cleanup_started
            try:
                if previous:
                    if previous_ack is not None:
                        t.save(previous['folder'] / 'superseded-ack.json', previous_ack)
                    t.save(previous['folder'] / 'superseded.json', t.encode(dict(byRequestSHA256=t.sha(raw), at=time.time(),
                        acknowledgementConsumed=False, sdkAdmitted=False, teardownAuthorized=False)))
                payload = {**request, 'phase': 'cleanup' if cleanup else 'setup', 'request_path': str(path)}
                state = page._publish(self.directory, payload, context=self.context, ready=True, cleanup=cleanup)
                self.state_raw = read(self.directory / 'state.json')
                t.require(t.load(self.state_raw) == state and read(path) == raw
                          and state['release_sha256'] == t.sha(raw), 'published prompt differs from retained request')
                routing_raw = t.encode(dict(originalPhase=phase, uiPhase=payload['phase'], requestSHA256=t.sha(raw),
                    bindingSHA256=t.sha(self.binding_raw), generation=state['generation'], pageSHA256=t.sha(self.state_raw),
                    releaseLabel=state['release_label'], deadline=self.deadline, cleanupStarted=self.cleanup_started))
                t.save(folder / 'page.json', self.state_raw)
                t.save(folder / 'routing.json', routing_raw)
                self.pending = dict(path=path, raw=raw, request=request, generation=state['generation'],
                                    folder=folder, routing_raw=routing_raw, ack_attempted=False)
                return state
            except Exception:
                # A publication without its durable join must never remain actionable.
                page._publish(self.directory, {'instruction': 'Prompt publication failed. Keep input released.'},
                              context=self.context, cleanup=self.cleanup_started)
                self.state_raw = read(self.directory / 'state.json')
                self.pending = None
                raise

    def acknowledgement(self):
        with self.locked():
            t.require(self.pending is not None and not self.pending['ack_attempted'],
                      'acknowledgement collection already attempted')
            raw, state_raw = self.verify_pending()
            if raw is None:
                return None
            pending = self.pending
            # Even the first write may fail. Do not admit a second collection
            # after partial publication; preserve the real reply for cleanup.
            pending['ack_attempted'] = True
            t.save(pending['folder'] / 'ack.json', raw)
            t.save(pending['folder'] / 'ack-page.json', state_raw)
            t.save(pending['folder'] / 'consumed.json', t.encode(dict(requestSHA256=t.sha(pending['raw']),
                ackSHA256=t.sha(raw), bindingSHA256=t.sha(self.binding_raw), at=time.time(),
                generation=pending['generation'], sdkAdmitted=False, teardownAuthorized=False)))
            self.state_raw = state_raw
            self.pending = None
            return raw

    def status(self, instruction):
        with self.locked():
            t.require(self.pending is None, 'status cannot retire a pending acknowledgement')
            t.require(read(self.directory / 'state.json') == self.state_raw, 'unowned operator page generation')
            state = page._publish(self.directory, {'instruction': instruction}, context=self.context,
                                  cleanup=self.cleanup_started)
            self.state_raw = read(self.directory / 'state.json')
            return state

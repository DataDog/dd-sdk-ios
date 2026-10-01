"""Physical H10 still-source bindings; the tool owner performs actual calls.

Requests never contain activation or input. Returned pixels qualify marker
visibility only; native lifecycle, whole-window usability and cleanup are separate.
"""
import ast
import copy
import json
import math
from pathlib import Path
import re
import sys
import time
import uuid

import operation_display as media
import operation_setup as setup
import operation_transport as t
import scene_background_capture as capture
import scene_background_display as display
import scene_background_protocol as protocol

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'automatic-coverage'))
import human_supported_session as supported

TOOLS = dict(start=supported.START, capture=supported.CAPTURE, end=supported.END)


def sources():
    root = Path(__file__).resolve().parents[1]
    modules = {name: Path(module.__file__).resolve() for name,module in tuple(sys.modules.items())
               if getattr(module,'__file__',None) and not name.startswith('test_')
               and Path(module.__file__).suffix == '.py'
               and Path(module.__file__).resolve().is_relative_to(root)}
    pending = [Path(__file__).resolve()]; result = {}
    while pending:
        path = pending.pop()
        if str(path) in result: continue
        raw = setup.read(path,maximum=capture.MAXIMUM_BYTES); result[str(path)] = t.sha(raw)
        for node in ast.walk(ast.parse(raw)):
            names = [a.name for a in node.names] if isinstance(node,ast.Import) else \
                [node.module] if isinstance(node,ast.ImportFrom) and node.level == 0 else []
            pending.extend(modules[name] for name in names if name in modules)
    return result


def finite(value): return type(value) in (int,float) and math.isfinite(value)


class Source:
    def __init__(self, folder, binding, identity, *, request_seconds, expected_sources):
        protocol.identity(identity)
        t.require(set(binding) == {'owner','device','udid','bundle','pid','run_id','plan_sha256','product_sha256'}
                  and all(isinstance(binding[k],str) and binding[k] for k in
                          ['owner','device','udid','bundle','run_id'])
                  and type(binding['pid']) is int and binding['pid'] == identity['processID']
                  and binding['run_id'] == identity['runID']
                  and all(t.digest(binding[k]) for k in ['plan_sha256','product_sha256']),
                  'H10 physical source identity differs')
        t.require(finite(request_seconds) and 0 < request_seconds <= 1800
                  and expected_sources == LOADED_SOURCES == sources(), 'H10 source closure or budget differs')
        self.folder = Path(folder).resolve()
        t.require(self.folder.is_dir() and not list(self.folder.iterdir()), 'H10 source output consumed')
        self.binding = copy.deepcopy(binding); self.identity = copy.deepcopy(identity)
        self.sources = dict(expected_sources); self.seconds = request_seconds
        self.execution = identity['executionDeadlineMilliseconds']/1000
        self.cleanup = identity['cleanupDeadlineMilliseconds']/1000
        self.context = t.encode(dict(binding=self.binding,identity=self.identity,sources=self.sources,
                                     request_seconds=self.seconds,execution=self.execution,cleanup=self.cleanup))
        self.original_context = self.context
        self.records = {}; self.requests = {}; self.claims = {}; self.responses = {}
        self.resolved = {}; self.cleanup_start = None
        self.key = None; self.start_response = None; self.failed = False; self.ended = False
        self.start_qualified = False
        self.tokens = set(); self.owners = None; self.accepted = []; self.capture_count = 0
        self.save(self.folder/'context.json',self.context); self.live('execution')

    def save(self, path, raw):
        # Remember issued bytes before publication, never replacement bytes.
        self.records[str(path)] = t.sha(raw)
        try:
            t.save(path,raw)
            t.require(setup.read(path,maximum=media.MAX_BYTES) == raw, 'H10 source publication changed')
        except Exception:
            self.failed = True
            raise

    def live(self, phase):
        try:
            original = t.load(self.original_context)
            cutoff = original['cleanup'] if phase == 'cleanup' else original['execution']
            t.require(phase in ['execution','cleanup'] and time.time() < cutoff
                      and (phase == 'cleanup' or not self.failed), 'H10 failed or original source cutoff expired')
            t.require(self.folder.is_dir() and not any(p.is_symlink() for p in [self.folder,*self.folder.parents])
                      and self.binding == original['binding'] and self.identity == original['identity']
                      and self.cleanup == original['cleanup'], 'H10 original cleanup ownership changed')
            if phase == 'execution':
                t.require(self.context == self.original_context == t.encode(dict(binding=self.binding,
                          identity=self.identity,sources=self.sources,request_seconds=self.seconds,
                          execution=self.execution,cleanup=self.cleanup)) and self.sources == sources(),
                          'H10 source context changed')
                t.require(all(t.sha(setup.read(path,maximum=media.MAX_BYTES)) == digest
                              for path,digest in self.records.items()), 'H10 issued source evidence changed')
            return cutoff
        except Exception:
            self.failed = True
            raise

    def fail(self, folder, error):
        self.failed = True
        folder = Path(folder)
        if folder.parent != self.folder or folder.name not in self.requests: return
        if (folder/'result.json').exists(): (folder/'result.json').rename(folder/'invalidated-result.json')
        path = folder/'failure.json'
        if not path.exists(): t.save(path,t.encode(dict(state='INVALID',error_type=type(error).__name__,
            reason=str(error),native_acceptance=False,gates_closed=[])))

    def inspection(self, spec, *, expected_phase=None, issued_token=None):
        try: return self._inspection(spec,expected_phase=expected_phase,issued_token=issued_token)
        except Exception:
            self.failed = True
            raise

    def _inspection(self, spec, *, expected_phase=None, issued_token=None):
        t.require(set(spec) == {'request','reply','descriptor','evidence_directory','phase_replies'},
                  'H10 inspection source fields differ')
        request,reply,descriptor = [media.verified_ref(spec[k],capture.MAXIMUM_BYTES)
                                    for k in ['request','reply','descriptor']]
        _, reference = protocol.reply(reply,request,received_ms=int(time.time()*1000))
        actual = capture.read_capture(spec['evidence_directory'],reference,self.identity)
        consumed = [t.sha(media.verified_ref(ref,capture.MAXIMUM_BYTES)) for ref in spec['phase_replies']]
        checked = display.descriptor(descriptor,request,capture.decode(actual['capture']['before']),self.identity,consumed)
        phase = checked['request']['challenge']['phase']
        after,events,names,_ = display.native(capture.decode(actual['capture']['after']),self.identity['runID'],
                                             checked['native_phase'],checked['owners'])
        expected_phase = self.capture_count if expected_phase is None else expected_phase
        t.require(phase == expected_phase and len(consumed) == phase
                  and actual['terminal'] is None and actual['capture']['boundary'] == checked['request']['challenge']['name']
                  and after == checked['owners'] and names == checked['names']
                  and events[:len(checked['events'])] == checked['events']
                  and (self.owners is None or after == self.owners), 'H10 source inspection or owners differ')
        token = checked['descriptor']['token']; t.require(token not in self.tokens or token == issued_token, 'H10 inspect token reused')
        refs = [spec[k] for k in ['request','reply','descriptor']]+spec['phase_replies']
        frozen = {ref['path']: t.sha(media.verified_ref(ref,capture.MAXIMUM_BYTES)) for ref in refs}
        path = Path(spec['evidence_directory'])/reference['name']
        frozen[str(path)] = t.sha(capture.read_reference(spec['evidence_directory'],reference))
        return checked, frozen

    def issue(self, operation, *, inspection=None):
        phase = 'cleanup' if operation == 'end' else 'execution'; cutoff = self.live(phase)
        t.require(operation in TOOLS and not self.ended
                  and (all(label in self.resolved for label in self.claims) if operation == 'end'
                       else all(label in self.responses for label in self.requests)),
                  'H10 unresolved or ended tool call')
        checked = None; frozen = {}
        if operation == 'start':
            t.require(not self.requests and inspection is None, 'H10 Start already consumed')
            label = 'start'; arguments = dict(deviceIdentifier=self.binding['device'],
                                             sessionIdentifier='RUM H10 '+self.binding['run_id'])
        else:
            t.require(self.key is not None and self.start_response is not None, 'H10 actual physical session unavailable')
            if operation == 'end':
                t.require('end' not in self.requests and inspection is None, 'H10 End already consumed')
                t.require(self.cleanup_start is not None and self.cleanup_start['key'] == self.key,
                          'H10 original actual cleanup key changed')
                t.require(self.cleanup_start['request'] == t.sha(self.requests['start'])
                          and self.cleanup_start['claim'] == t.sha(self.claims['start'])
                          and self.cleanup_start['observation'] == t.sha(self.resolved['start'])
                          and supported.tool_value(t.load(self.resolved['start'])['actual_return'])['interactionSessionKey']
                              == self.key, 'H10 retained actual Start ownership changed')
                label = 'end'; arguments = dict(interactionSessionKey=self.key)
            else:
                t.require(self.start_qualified and self.capture_count < 4 and inspection is not None
                          and len(self.accepted) == self.capture_count, 'H10 capture start/order unqualified')
                checked,frozen = self.inspection(inspection)
                label = 'capture-'+str(self.capture_count); arguments = dict(interactSessionKey=self.key)
        now = time.time(); folder = self.folder/label; folder.mkdir()
        value = dict(kind='H10_STILL_TOOL_REQUEST',operation=operation,tool=TOOLS[operation],arguments=arguments,
            request_id=str(uuid.uuid4()),binding=self.binding,identity=self.identity,session_root=str(self.folder),
            start_response=self.start_response,inspection=copy.deepcopy(inspection),
            capture_index=self.capture_count if operation == 'capture' else None,
            inspected_artifacts=frozen,issued_at=now,deadline=min(cutoff,now+self.seconds))
        raw = t.encode(value); self.requests[label] = raw
        try:
            self.save(folder/'request.json',raw)
            if checked is not None:
                self.tokens.add(checked['descriptor']['token']); self.owners = checked['owners']; self.capture_count += 1
            self.live(phase)
            return folder/'request.json'
        except Exception as error: self.fail(folder,error); raise

    def request(self, path):
        try: return self._request(path)
        except Exception:
            self.failed = True
            raise

    def _request(self, path):
        path = Path(path); label = path.parent.name
        t.require(path == self.folder/label/'request.json' and label in self.requests
                  and setup.read(path) == self.requests[label], 'H10 request replaced or redirected')
        value = t.load(self.requests[label]); phase = 'cleanup' if value['operation'] == 'end' else 'execution'
        self.live(phase)
        t.require(all(t.sha(setup.read(p,maximum=capture.MAXIMUM_BYTES)) == digest
                      for p,digest in value['inspected_artifacts'].items()), 'H10 original inspection changed')
        return label,value,phase

    def dispatch(self, path, owner):
        label,value,phase = self.request(path)
        t.require(owner == self.binding['owner'] and label not in self.claims
                  and all(k in (self.resolved if phase == 'cleanup' else self.responses) for k in self.claims),
                  'H10 foreign or overlapping tool dispatch')
        claim = t.encode(dict(request=t.sha(self.requests[label]),owner=owner,tool=value['tool'],
                              arguments=value['arguments'],at=time.time()))
        self.claims[label] = claim
        try:
            self.save(Path(path).parent/'dispatch.json',claim); self.live(phase)
            return dict(tool=value['tool'],arguments=copy.deepcopy(value['arguments']),deadline=value['deadline'])
        except Exception as error: self.fail(Path(path).parent,error); raise

    def publish(self, path, observation):
        """The same tool owner supplies the complete actual awaited observation."""
        try: return self._publish(path, observation)
        except Exception as error: self.fail(Path(path).parent,error); raise

    def _publish(self, path, observation):
        path = Path(path); label = path.parent.name; folder = path.parent
        t.require(path == self.folder/label/'request.json' and label in self.claims
                  and label not in self.responses, 'H10 unclaimed or repeated tool return')
        t.require(label not in self.resolved, 'H10 repeated actual tool return')
        # Retain an actual, resolved owned call before publication can fail. This
        # authorizes only End of that session, never capture or Start acceptance.
        value = t.load(self.requests[label]); claim = t.load(self.claims[label])
        actual_raw = t.encode(observation['actual_return']); raw = t.encode(observation)
        ownership_error = None
        try:
            t.require(set(observation) == {'owner','tool','arguments','started_at','finished_at','actual_return'}
                      and observation['owner'] == claim['owner'] == self.binding['owner']
                      and observation['tool'] == claim['tool'] == value['tool']
                      and observation['arguments'] == claim['arguments'] == value['arguments'],
                      'H10 actual returned ownership differs')
            clocks = [value['issued_at'],claim['at'],observation['started_at'],observation['finished_at'],time.time()]
            t.require(all(finite(v) for v in clocks) and clocks == sorted(clocks), 'H10 actual returned clocks differ')
            self.resolved[label] = raw
        except Exception as error: ownership_error = error
        candidate = observation['actual_return'].get('structuredContent')
        if not isinstance(candidate,dict):
            try: candidate = supported.tool_value(observation['actual_return'])
            except Exception: candidate = {}
        if ownership_error is None and label == 'start' and observation['actual_return'].get('isError') is not True \
                and candidate.get('deviceIsSimulator') is False \
                and candidate.get('deviceUUID') in [self.binding['device'],self.binding['udid']] \
                and isinstance(candidate.get('interactionSessionKey'),str) and candidate['interactionSessionKey'].strip():
            self.key = candidate['interactionSessionKey']
            self.cleanup_start = dict(key=self.key,request=t.sha(self.requests[label]),claim=t.sha(self.claims[label]),
                                      observation=t.sha(raw),actual_return=t.sha(actual_raw))
            self.start_response = dict(kind='CLEANUP_ONLY_ACTUAL_START',sha256=t.sha(raw))
        # Preserve the actual return before any clock, source or artifact acceptance.
        self.save(folder/'tool-result.json',actual_raw)
        self.save(folder/'observation.json',raw)
        if ownership_error is not None: raise ownership_error
        copied = {}; errors = []
        for name in ['hierarchy','screenshot','logs','thumbnailScreenshot']:
            original = candidate.get(name+'Path')
            if not original: continue
            try:
                source = Path(original); t.require(source.is_absolute() and not source.is_symlink(), 'returned path invalid')
                resolved = source.resolve(); data = setup.read(source,maximum=media.MAX_BYTES)
                target = folder/('returned-'+name+source.suffix); self.save(target,data)
                t.require(source.resolve() == resolved and setup.read(source,maximum=media.MAX_BYTES) == data,
                          'returned source changed while freezing')
                copied[name] = dict(source_path=original,path=str(target),sha256=t.sha(data))
            except Exception as error: errors.append(dict(artifact=name,error_type=type(error).__name__,reason=str(error)))
        response = dict(observation=t.sha(raw),actual_return=t.sha(actual_raw),request=t.sha(self.requests[label]),
                        claim=t.sha(self.claims[label]),artifacts=copied,artifact_errors=errors,published_at=time.time())
        encoded = t.encode(response); self.responses[label] = encoded; self.save(folder/'response.json',encoded)
        if label == 'start' and self.cleanup_start is not None:
            self.start_response = dict(path=str(folder/'response.json'),sha256=t.sha(encoded))
        return response

    def returned(self, path):
        label,value,phase = self.request(path); folder = Path(path).parent
        t.require(label in self.responses and label in self.claims, 'H10 tool return absent')
        observed = t.load(setup.read(folder/'observation.json',maximum=capture.MAXIMUM_BYTES))
        claim = t.load(self.claims[label]); response = t.load(self.responses[label])
        t.require(t.encode(observed) == self.resolved.get(label)
                  and setup.read(folder/'observation.json',maximum=capture.MAXIMUM_BYTES) == self.resolved[label]
                  and t.sha(setup.read(folder/'tool-result.json',maximum=capture.MAXIMUM_BYTES)) == response['actual_return']
                  and t.sha(self.resolved[label]) == response['observation']
                  and setup.read(folder/'response.json') == self.responses[label]
                  and setup.read(folder/'dispatch.json') == self.claims[label], 'H10 actual cleanup return replaced')
        t.require(set(observed) == {'owner','tool','arguments','started_at','finished_at','actual_return'}
                  and observed['owner'] == claim['owner'] == self.binding['owner']
                  and observed['tool'] == claim['tool'] == value['tool']
                  and observed['arguments'] == claim['arguments'] == value['arguments']
                  and not response['artifact_errors'], 'H10 actual returned call differs')
        clocks = [value['issued_at'],claim['at'],observed['started_at'],observed['finished_at'],response['published_at'],time.time()]
        t.require(all(finite(v) for v in clocks) and clocks == sorted(clocks) and clocks[-1] < value['deadline'],
                  'H10 source return exceeded its original resource budget')
        actual = supported.tool_value(t.load(setup.read(folder/'tool-result.json',maximum=capture.MAXIMUM_BYTES)))
        self.live(phase); return value,response,actual

    def accept_start(self):
        folder = self.folder/'start'
        try:
            t.require(not self.start_qualified, 'H10 Start acceptance already consumed')
            self.returned(folder/'request.json'); t.require(self.key is not None, 'H10 Start did not identify the physical device')
            self.start_qualified = True
            return dict(state='PHYSICAL_TOOL_SESSION_BOUND',native_acceptance=False)
        except Exception as error: self.fail(folder,error); raise

    def accept_capture(self, path, binary, binary_sha256):
        folder = Path(path).parent
        try:
            request,response,value = self.returned(path)
            t.require(self.start_qualified and request['capture_index'] == len(self.accepted)
                      and request['operation'] == 'capture' and value.get('applicationState') in ['NotRun','Running']
                      and set(response['artifacts']) >= {'hierarchy','screenshot'}, 'H10 current capture unavailable')
            hierarchy = setup.read(response['artifacts']['hierarchy']['path']).decode()
            headers = re.findall(r'^Application bundle identifier: ([^\n]+)\nApplication UI orientation: [^\n]*\nApplication, pid: ([0-9]+),',hierarchy,re.MULTILINE)
            t.require([pid for bundle,pid in headers if bundle == self.binding['bundle']] == [str(self.binding['pid'])],
                      'H10 hierarchy does not identify the original task PID')
            screenshot = response['artifacts']['screenshot']['path']
            t.require(setup.read(screenshot,maximum=media.MAX_BYTES).startswith(b'\x89PNG\r\n\x1a\n'), 'H10 full-size image is not PNG')
            checked,_ = self.inspection_for_request(request)
            proof = media.decode(binary,binary_sha256,'IMAGE',screenshot,folder/'decode',
                min(1800,request['deadline']-time.time()),source_sha256=media.sha(Path(media.__file__).with_suffix('.swift')))
            frames = media.checked(proof,'IMAGE'); t.require(len(frames) == 1, 'H10 still capture has multiple frames')
            pixels = display.pixels(frames[0],checked['descriptor'],self.old_a if request['capture_index'] == 1 else None)
            if request['capture_index'] == 0: self.old_a = checked['descriptor']['payloads']['scene-A']
            self.live('execution'); self.request(path)
            result = dict(state='PASS_PHYSICAL_STILL_SOURCE_COMPONENT',request=t.sha(self.requests[folder.name]),
                response=t.sha(self.responses[folder.name]),image=proof,pixels=pixels,
                application_state=value['applicationState'],native_acceptance=False,gates_closed=[])
            raw = t.encode(result); self.save(folder/'result.json',raw); self.live('execution'); self.request(path)
            self.accepted.append(dict(path=str(folder/'result.json'),sha256=t.sha(raw))); return result
        except Exception as error: self.fail(folder,error); raise

    def inspection_for_request(self, request):
        # Revalidate the issued inspection without consuming another capture slot.
        phase = request['capture_index']
        t.require(type(phase) is int and 0 <= phase < self.capture_count, 'H10 issued capture phase differs')
        token = t.load(media.verified_ref(request['inspection']['descriptor'],capture.MAXIMUM_BYTES))['token']
        t.require(token in self.tokens, 'H10 issued inspect token absent')
        return self.inspection(request['inspection'],expected_phase=phase,issued_token=token)

    def accept_end(self, completion):
        folder = self.folder/'end'
        try:
            _,_,actual = self.returned(folder/'request.json')
            t.require(actual.get('userMessage') == 'Session stopped' and completion == dict(
                owner=self.binding['owner'],pending_calls=0,input_commands=0,
                final_response=dict(path=str(folder/'response.json'),sha256=t.sha(self.responses['end'])),
                at=completion.get('at')) and finite(completion['at'])
                and t.load(self.responses['end'])['published_at'] <= completion['at'] <= time.time() < self.cleanup
                and set(self.claims) == set(self.resolved), 'H10 actual End or zero-pending completion unavailable')
            completed = t.encode(completion)
            self.save(self.folder/'worker-completed.json',completed)
            self.returned(folder/'request.json')
            t.require(setup.read(self.folder/'worker-completed.json') == completed,
                      'H10 final worker completion changed')
            value = dict(state='SUPPORTED_SOURCE_SESSION_STOPPED',captures=len(self.accepted),input_commands=0,
                native_acceptance=False,task_cleanup_authorized=False,gates_closed=[])
            raw = t.encode(value); self.save(folder/'result.json',raw)
            self.returned(folder/'request.json')
            t.require(setup.read(self.folder/'worker-completed.json') == completed
                      and setup.read(folder/'result.json') == raw, 'H10 terminal cleanup publication changed')
            self.live('cleanup'); self.ended = True; return value
        except Exception as error: self.fail(folder,error); raise


LOADED_SOURCES = sources()

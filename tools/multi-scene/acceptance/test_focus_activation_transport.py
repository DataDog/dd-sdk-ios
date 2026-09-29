"""Offline protocol controls. Actual Swift code runs with synthetic input adapters."""
import base64
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import focus_activation_fixture as fixture
import focus_activation_transport as p
import operation_transport as t
from test_focus_activation_contract import snapshot

HERE=Path(__file__).resolve().parent
NATIVE={'scene-A':'11111111-1111-1111-1111-111111111111','scene-B':'22222222-2222-2222-2222-222222222222'}
INSTALLED=t.encode(dict(runID='focus-native-tests',processID=123,sourceRevision='a'*40,boundary='before-sdk-initialization'))
IDENTITY=dict(schemaVersion=1,runID='focus-native-tests',processID=123,scenarioID=p.SCENARIO,profile=p.PROFILE,
              sourceRevision='a'*40,installedCodeSHA256=t.sha(INSTALLED),challengeID='11111111-1111-4111-8111-111111111111',
              executionDeadlineMilliseconds=20000,cleanupDeadlineMilliseconds=30000)


def start_snapshot():
    s=snapshot('scene-A',NATIVE)
    for key in ['scenes','input','inventory']:s[key]=s[key][:1]
    s['continuity']['owners']=s['continuity']['owners'][:1]
    s['connectedSceneIDs']=[NATIVE['scene-A']]
    return s


def failed_layout(state):
    value=snapshot('scene-A',NATIVE)
    value['scenes'][1]['activationState']=state
    peer=value['inventory'][1];peer['activationState']=state
    if state == 'foreground-active':
        peer['keyWindowIdentity']=peer['windows'][0]['identity'];peer['windows'][0]['key']=True
    return value


def response(sent,values=None):
    m=t.load(sent);stop=m['operation']=='stop';value=values or (snapshot('scene-A',NATIVE) if stop else start_snapshot())
    raw=t.encode(value)
    return dict(identity=m['identity'],requestSHA256=t.sha(sent),commandID=m['commandID'],
                outcome='stopped-idle' if stop else 'armed',driver=dict(requested=stop,stopped=stop),
                observation=dict(before=base64.b64encode(raw).decode(),after=base64.b64encode(raw).decode(),idle=True))


def declaration(source,anchor):
    start=source.index(anchor);brace=source.index('{',start);level=1;end=brace+1
    while level:
        level += (source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]


def swift_types():
    # Extract current native value declarations; no handwritten shadow of their fields.
    source=(fixture.PROBE/'Sources/Harness/ProbePhysicalTopologyAdmission.swift').read_text()
    value='\n'.join(declaration(source,'internal struct '+name+':') for name in
                    ['ProbePhysicalSceneObservation','ProbePhysicalInputWindow','ProbePhysicalWindowInventory','ProbePhysicalSceneInventory'])
    value+='\ninternal enum ProbePhysicalOperationEventLedger {\n'+ '\n'.join(
        declaration(source,'struct '+name+':') for name in ['Owner','Event','Snapshot'])+'\n}\n'
    start=source.index('internal struct ProbePhysicalInputSnapshot:')
    value+='\n'+source[start:source.index('    @MainActor\n    func idleFailure()',start)]+'}\n'
    geometry=(fixture.PROBE/'Sources/Harness/ProbeSignal.swift').read_text()
    value+='\n'+declaration(geometry,'internal struct ProbeGeometry:')
    return value


SWIFT_ADAPTERS=r"""
@MainActor final class ProbePhysicalOperationInput {
    var values: [ProbePhysicalInputSnapshot]
    init(_ values: [ProbePhysicalInputSnapshot]) { self.values = values }
    func snapshot() -> ProbePhysicalInputSnapshot {
        if values.count > 1 { return values.removeFirst() }
        return values[0]
    }
}
struct TestTerminal: Codable { let state: String }
@MainActor final class TestDriver {
    struct State { var requested = false; var stopped = false; var terminalBeforeStop: TestTerminal? }
    var cleanupState = State()
    func stopForCleanup() { cleanupState.requested = true }
}
@MainActor enum ProbeRuntime { static let runID = "focus-native-tests"; static let scenarioDriver: TestDriver? = .init() }
"""

SWIFT_MAIN=r"""
@main struct FocusNativeControls {
    enum TestFailure: Error { case failed(String) }
    @MainActor static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let decoder = JSONDecoder()
        let identity = try decoder.decode(ProbeFocusControl.Identity.self, from: Data(contentsOf: out.appendingPathComponent("identity.json")))
        let initial = try decoder.decode(ProbePhysicalInputSnapshot.self, from: Data(contentsOf: out.appendingPathComponent("initial.json")))
        let final = try decoder.decode(ProbePhysicalInputSnapshot.self, from: Data(contentsOf: out.appendingPathComponent("final.json")))
        var checks: [String] = []
        func check(_ condition: Bool, _ name: String) throws { guard condition else { throw TestFailure.failed(name) }; checks.append(name) }
        final class State {
            var requested = false; var stopped = false; var ready = true; var idle = true; var stops = 0
        }
        func make(_ name: String, _ state: State) throws -> ProbeFocusControl {
            try ProbeFocusControl(directory: out.appendingPathComponent(name), identity: identity, now: 10000, observe: { operation in
                let input = ProbePhysicalOperationInput([operation == "arm" ? initial : final])
                let actual = try ProbeFocusSession.witness(input, stage: operation)
                if operation == "arm" ? !state.ready : !state.idle {
                    return .init(before: actual.before, after: actual.after, idle: false, reason: "synthetic held input")
                }
                return actual
            }, stop: { state.requested = true; state.stops += 1 },
               driver: { .init(requested: state.requested, stopped: state.stopped, terminal: nil) })
        }
        func publish(_ channel: ProbeFocusControl, _ request: ProbeFocusControl.Request, raw: Data? = nil) throws -> String {
            let bytes = try raw ?? ProbeFocusControl.encode(request), sha = ProbeFocusControl.sha(bytes)
            try bytes.write(to: channel.directory.appendingPathComponent(sha + ".json"), options: .atomic)
            try Data(sha.utf8).write(to: channel.directory.appendingPathComponent(request.operation + ".request"), options: .atomic)
            return sha
        }
        func request(_ operation: String, commandID: String = UUID().uuidString.lowercased()) -> ProbeFocusControl.Request {
            .init(identity: identity, commandID: commandID, operation: operation)
        }
        func exists(_ c: ProbeFocusControl, _ sha: String) -> Bool {
            FileManager.default.fileExists(atPath: c.directory.appendingPathComponent(sha + ".reply.json").path)
        }
        let state=State(), c=try make("positive",state)
        let armBytes=try Data(contentsOf: out.appendingPathComponent("python-arm.json"))
        let arm=try decoder.decode(ProbeFocusControl.Request.self,from:armBytes)
        let armSHA=try publish(c,arm,raw:armBytes)
        state.ready=false;try c.poll(now:10001)
        try check(c.phase == .waiting && !exists(c,armSHA),"arm_waits_for_actual_initial_idle")
        state.ready=true;try c.poll(now:10002)
        try check(c.phase == .armed && exists(c,armSHA) && c.admissionFailure(now:10003)==nil,"python_arm_publishes_before_driver_admission")
        let stop=request("stop"),stopSHA=try publish(c,stop)
        try c.poll(now:10004)
        try check(c.phase == .stopping && state.requested && !exists(c,stopSHA) && c.admissionFailure(now:10004) != nil,"stop_seals_work_before_driver_completion")
        state.stopped=true;state.idle=false;try c.poll(now:10005)
        try check(!exists(c,stopSHA),"stopped_driver_does_not_bypass_held_input")
        state.idle=true;try c.poll(now:10006)
        try check(c.phase == .closed && exists(c,stopSHA),"stopped_idle_reply_requires_original_task_and_input")
        try ProbeFocusControl.encode(stop).write(to:out.appendingPathComponent("swift-stop.json"))
        try Data(contentsOf:c.directory.appendingPathComponent(armSHA+".reply.json")).write(to:out.appendingPathComponent("swift-arm-reply.json"))
        try Data(contentsOf:c.directory.appendingPathComponent(stopSHA+".reply.json")).write(to:out.appendingPathComponent("swift-stop-reply.json"))
        try check(c.admissionFailure(now:10007) != nil,"no_resume_after_closed")
        do { _=try make("positive",State());throw TestFailure.failed("reused directory accepted") }
        catch ProbeFocusControl.Failure.file { checks.append("consumed_output_rejects") }

        let bothState=State(),both=try make("both",bothState)
        let bothArm=try publish(both,request("arm"));_ = try publish(both,request("stop"));try both.poll(now:10001)
        let rejected=try decoder.decode(ProbeFocusControl.Reply.self,from:Data(contentsOf:both.directory.appendingPathComponent(bothArm+".reply.json")))
        try check(both.phase == .stopping && bothState.requested && rejected.outcome == "rejected","stop_wins_same_tick_without_sdk_work")

        let partial=try make("partial",State()),pr=request("arm"),full=try ProbeFocusControl.encode(pr),hash=ProbeFocusControl.sha(full)
        try Data(hash.utf8).write(to:partial.directory.appendingPathComponent("arm.request"))
        try Data(full.prefix(full.count/2)).write(to:partial.directory.appendingPathComponent(hash+".json"));try partial.poll(now:10001)
        try check(partial.phase == .waiting && partial.failure == nil,"partial_publication_is_pending")
        try full.write(to:partial.directory.appendingPathComponent(hash+".json"));try partial.poll(now:10002)
        try check(partial.phase == .armed,"complete_same_publication_qualifies_once")
        _=try publish(partial,request("arm"))
        do { try partial.poll(now:10003);throw TestFailure.failed("replayed arm accepted") }
        catch ProbeFocusControl.Failure.replay { checks.append("replaced_arm_publication_stops_driver") }
        try check(partial.phase == .stopping,"replay_cannot_rearm")

        let failureState=State(),failed=try make("foreign",failureState)
        var foreign=try JSONSerialization.jsonObject(with:ProbeFocusControl.encode(request("arm"))) as! [String:Any]
        var other=foreign["identity"] as! [String:Any];other["processID"]=124;foreign["identity"]=other
        let bad=try JSONSerialization.data(withJSONObject:foreign,options:[.sortedKeys,.withoutEscapingSlashes])
        _=try publish(failed,request("arm"),raw:bad)
        do { try failed.poll(now:10001);throw TestFailure.failed("foreign identity accepted") }
        catch ProbeFocusControl.Failure.request { checks.append("foreign_process_cannot_arm") }
        failureState.stopped=true;let cleanupSHA=try publish(failed,request("stop"));try failed.poll(now:10002)
        try check(failed.phase == .closed && exists(failed,cleanupSHA) && failed.failure != nil,"failed_scenario_can_still_prove_separate_idle_cleanup")

        let expiryState=State(),expiry=try make("expiry",expiryState)
        _=try publish(expiry,request("arm"));try expiry.poll(now:20000)
        try check(expiryState.requested && expiry.phase == .stopping && expiry.admissionFailure(now:10000) != nil,"expired_execution_cannot_be_extended_by_clock_rewind")
        try expiry.poll(now:30000)
        try check(expiry.phase == .closed && FileManager.default.fileExists(atPath:expiry.directory.appendingPathComponent("expired.json").path),"expired_cleanup_persists_unqualified_state")

        let staleState=State(),stale=try make("duplicate-key",staleState),good=try ProbeFocusControl.encode(request("arm"))
        let duplicate=Data(("{\"operation\":\"arm\","+String(decoding:good.dropFirst(),as:UTF8.self)).utf8)
        _=try publish(stale,request("arm"),raw:duplicate)
        do { try stale.poll(now:10001);throw TestFailure.failed("duplicate key accepted") }
        catch ProbeFocusControl.Failure.request { checks.append("duplicate_or_unknown_outer_fields_reject") }

        try check(ProbeFocusSession.idleFailure(initial,stage:"arm")==nil,"native_initial_single_owner_passes")
        try check(ProbeFocusSession.idleFailure(final,stage:"stop")==nil,"native_cleanup_accepts_declared_background_peer")
        try check(ProbeFocusSession.idleFailure(final,stage:"arm") != nil,"native_start_rejects_restored_peer")
        let variants=try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("idle-variants.json"))) as! [String:Any]
        for (name,value) in variants {
            let raw=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),snapshot=try decoder.decode(ProbePhysicalInputSnapshot.self,from:raw)
            try check(ProbeFocusSession.idleFailure(snapshot,stage:"stop") != nil,"native_idle_rejects_"+name)
        }
        for state in ["foreground-active", "foreground-inactive"] {
            let layout=try decoder.decode(ProbePhysicalInputSnapshot.self,from:Data(contentsOf:out.appendingPathComponent("failed-layout-"+state+".json")))
            try check(ProbeFocusSession.idleFailure(layout,stage:"stop")==nil,"idle_failed_layout_can_cleanup_"+state)
        }
        let drift=try decoder.decode(ProbePhysicalInputSnapshot.self,from:Data(contentsOf:out.appendingPathComponent("geometry-drift.json")))
        let witness=try ProbeFocusSession.witness(ProbePhysicalOperationInput([final,drift]),stage:"stop")
        try check(witness.idle && witness.before != witness.after,"native_idle_preserves_float_bytes_without_exact_geometry_gate")
        try ProbeFocusControl.encode(checks).write(to:out.appendingPathComponent("swift-checks.json"))
        print("PASS \(checks.count) actual Swift protocol and idle controls")
    }
}
"""


class TransportTests(unittest.TestCase):
    def test_exact_challenge_binds_installed_process_and_cutoffs(self):
        expected=dict(run_id=IDENTITY['runID'],process_id=123,revision='a'*40,execution_ms=20000,cleanup_ms=30000)
        self.assertEqual(p.challenge(t.encode(IDENTITY),INSTALLED,**expected),IDENTITY)
        for key,value in [('processID',True),('profile','old'),('executionDeadlineMilliseconds',20001),('challengeID','OLD'),('installedCodeSHA256','0'*64)]:
            bad=IDENTITY|{key:value}
            with self.subTest(key=key),self.assertRaises(ValueError):p.challenge(t.encode(bad),INSTALLED,**expected)

    def test_wrong_identity_cutoff_and_rejected_reply(self):
        sent=p.request(IDENTITY,'stop');good=response(sent)
        self.assertEqual(p.reply(t.encode(good),sent,received_at_ms=10006)['cleanup'],'PENDING')
        for key,value in [('requestSHA256','0'*64),('commandID','foreign'),('outcome','rejected'),('driver',dict(requested=True,stopped=False))]:
            with self.subTest(key=key),self.assertRaises(ValueError):p.reply(t.encode(good|{key:value}),sent,received_at_ms=10006)
        with self.assertRaises(ValueError):p.reply(t.encode(good),sent,received_at_ms=30000)
        with self.assertRaises(ValueError):p.reply(t.encode(good),p.request(IDENTITY,'stop'),received_at_ms=10006)

    def test_idle_rejects_contacts_transitions_replacement_and_foreign_inventory(self):
        for mutate in [lambda s:s['input'][0].update(touches=1),lambda s:s['input'][0].update(transitioning=True),
                       lambda s:s['input'][0].update(resizing=True),lambda s:s['input'][0].update(reliable=False),
                       lambda s:s['input'][0].update(rootIdentity='replaced'),lambda s:s['inventory'][0].update(keyWindowIdentity='other'),
                       lambda s:s['connectedSceneIDs'].append('foreign')]:
            value=snapshot('scene-A',NATIVE);mutate(value);sent=p.request(IDENTITY,'stop')
            with self.assertRaises(ValueError):p.reply(t.encode(response(sent,value)),sent,received_at_ms=10006)

    def test_unknown_auxiliary_window_and_fractional_geometry_are_preserved(self):
        value=snapshot('scene-A',NATIVE);value['inventory'][0]['windows'].append(dict(identity='auxiliary',key=False))
        sent=p.request(IDENTITY,'stop');reply=response(sent,value);after=copy.deepcopy(value)
        after['scenes'][0]['geometry']['width']+=0.000000000001
        reply['observation']['after']=base64.b64encode(t.encode(after)).decode()
        result=p.reply(t.encode(reply),sent,received_at_ms=10006)
        self.assertNotEqual(result['before_sha256'],result['after_sha256'])
        after['input'][0]['revision']+=1;reply['observation']['after']=base64.b64encode(t.encode(after)).decode()
        with self.assertRaises(ValueError):p.reply(t.encode(reply),sent,received_at_ms=10006)

    def test_failed_layout_allows_idle_cleanup_without_qualifying_scenario(self):
        import focus_activation_contract as contract
        from test_focus_activation_contract import fixture as local_fixture, mutate_guard
        from acceptance_common import Rejected
        for state in ['foreground-active','foreground-inactive']:
            value=failed_layout(state);sent=p.request(IDENTITY,'stop')
            self.assertEqual(p.reply(t.encode(response(sent,value)),sent,received_at_ms=10006)['overall'],'UNQUALIFIED')
            rows=local_fixture()
            # The first marker targets B; change its peer A consistently in all native inventories.
            def invalid_marker(v):
                v['scenes'][0]['activationState']=state;v['inventory'][0]['activationState']=state
                if state == 'foreground-active':
                    v['inventory'][0]['keyWindowIdentity']=v['inventory'][0]['windows'][0]['identity']
                    v['inventory'][0]['windows'][0]['key']=True
            mutate_guard(rows,invalid_marker)
            with self.subTest(state=state),self.assertRaises(Rejected):contract.validate_local(rows,'focus-unit-only',profile=p.PROFILE)

    def test_malformed_or_substituted_raw_observations_reject(self):
        sent=p.request(IDENTITY,'stop');reply=response(sent)
        for value in ['@invalid',base64.b64encode(b'{"input":[],"input":[]}').decode()]:
            reply['observation']['after']=value
            with self.assertRaises(ValueError):p.reply(t.encode(reply),sent,received_at_ms=10006)

    def test_actual_swift_channel_and_native_idle(self):
        preserved=os.environ.get('FOCUS_CONTROL_TEST_OUTPUT')
        temporary=None if preserved else tempfile.TemporaryDirectory(prefix='focus-native-controls-')
        out=Path(preserved or temporary.name);out.mkdir(exist_ok=True)
        try:
            values={'identity.json':IDENTITY,'initial.json':start_snapshot(),'final.json':snapshot('scene-A',NATIVE)}
            variants={}
            for name,key,value in [('touches','touches',1),('transition','transitioning',True),('resize','resizing',True),
                                   ('unreliable','reliable',False),('detached','attached',False),('replaced-root','rootIdentity','other')]:
                s=snapshot('scene-A',NATIVE);s['input'][0][key]=value;variants[name]=s
            s=snapshot('scene-A',NATIVE);s['connectedSceneIDs'].append('foreign');variants['unknown-scene']=s
            s=snapshot('scene-A',NATIVE);s['inventory'][0]['keyWindowIdentity']='foreign';variants['wrong-key']=s
            values['idle-variants.json']=variants
            for state in ['foreground-active','foreground-inactive']:
                values['failed-layout-'+state+'.json']=failed_layout(state)
            drift=copy.deepcopy(values['final.json']);drift['scenes'][0]['geometry']['width']+=0.000000000001
            values['geometry-drift.json']=drift
            for name,v in values.items():(out/name).write_bytes(t.encode(v))
            sent=p.request(IDENTITY,'arm');(out/'python-arm.json').write_bytes(sent)
            source=(HERE/'focus_activation_channel.swift').read_text()+'\n'+swift_types()+'\n'+SWIFT_ADAPTERS+'\n'+(HERE/'focus_activation_session.swift').read_text()+'\n'+SWIFT_MAIN
            (out/'native-controls.swift').write_text(source)
            command=['xcrun','swiftc','-swift-version','5','-parse-as-library','-module-cache-path',str(out/'module-cache'),str(out/'native-controls.swift'),'-o',str(out/'native-controls')]
            build=subprocess.run(command,capture_output=True,timeout=90)
            (out/'compile.log').write_bytes(build.stdout+build.stderr)
            self.assertEqual(build.returncode,0,(build.stdout+build.stderr).decode())
            self.assertNotIn(b'warning:',build.stdout+build.stderr)
            run=subprocess.run([str(out/'native-controls'),str(out)],capture_output=True,timeout=20)
            (out/'native.log').write_bytes(run.stdout+run.stderr)
            self.assertEqual(run.returncode,0,(run.stdout+run.stderr).decode())
            self.assertEqual(len(json.loads((out/'swift-checks.json').read_text())),31)
            p.reply((out/'swift-arm-reply.json').read_bytes(),sent,received_at_ms=10006)
            p.reply((out/'swift-stop-reply.json').read_bytes(),(out/'swift-stop.json').read_bytes(),received_at_ms=10006)
        finally:
            if temporary:temporary.cleanup()


if __name__=='__main__':unittest.main()

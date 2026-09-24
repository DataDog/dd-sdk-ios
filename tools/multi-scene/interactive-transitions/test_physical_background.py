"""Failure controls for actual fixture lease source and Home-only admission."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import physical_build as build
import physical_background as background
import physical_runtime as runtime
from acceptance_common import Rejected


def receipt():
    return dict(schema_version=1, run_id='run', pid=17,
        token='34a0fc0e-8caa-43fb-bb1a-0d91c2ff24a0', checkpoint='background-10',
        started_uptime=100, deadline_uptime=105, finished_uptime=101.2,
        task_ended=True, state='PASS', reason='writer_completed')


class BackgroundControls(unittest.TestCase):
    def test_only_completed_same_run_same_process_bounded_writer_qualifies(self):
        value=receipt()
        self.assertEqual(background.validate_receipt(value,run_id='run',pid=17,checkpoint='background-10'),value)
        uppercase=receipt();uppercase['token']=uppercase['token'].upper();raw=json.dumps(uppercase)
        self.assertIs(background.validate_receipt(uppercase,run_id='run',pid=17,checkpoint='background-10'),uppercase)
        self.assertEqual(json.dumps(uppercase),raw)
        for key,value in [('run_id','old'),('pid',18),('pid',True),('checkpoint','background-11'),
            ('token','invalid'),('token',17),('token',None),
            ('token','34a0fc0e8caa43fbbb1a0d91c2ff24a0'),('token','{34a0fc0e-8caa-43fb-bb1a-0d91c2ff24a0}'),
            ('task_ended',False),('state','INVALID'),('reason','expired'),
            ('finished_uptime',105),('finished_uptime',99),('finished_uptime',float('nan')),
            ('deadline_uptime',106),('started_uptime',True)]:
            item=receipt();item[key]=value
            with self.subTest(key=key,value=value),self.assertRaises((ValueError,Rejected)):
                background.validate_receipt(item,run_id='run',pid=17,checkpoint='background-10')
        item=receipt();del item['task_ended']
        with self.assertRaises(Rejected):background.validate_receipt(item,run_id='run',pid=17,checkpoint='background-10')

    def test_overlay_preserves_settle_mapper_configuration_and_nonbackground_callbacks(self):
        path=build.original.BASE/'Fixture/Observation.swift';raw=path.read_bytes()
        source=build.original.variant.observation(raw,hashlib.sha256(raw).hexdigest())
        result=background.render(source,hashlib.sha256(source).hexdigest()).decode();original=source.decode()
        self.assertEqual(result.count('asyncAfter(deadline: .now() + 1.2)'),1)
        self.assertNotIn('Task { @MainActor in TransitionObservation.shared.close(reason: "background")',result)
        self.assertIn('defer { completion?(succeeded) }',result)
        a=original.index('        Datadog.initialize');b=original.index('        lifecycleObservers.append',a)
        self.assertIn(original[a:b],result)
        a=original.index('    static func hit(')
        self.assertIn(original[a:],result)
        self.assertEqual(path.read_bytes(),raw)
        with self.assertRaises(Rejected):background.render(source,'wrong')
        with self.assertRaises(Rejected):background.render(raw,hashlib.sha256(raw).hexdigest())

    def test_home_only_cannot_be_compared_or_admit_candidate(self):
        with patch.object(runtime,'verify',return_value=dict(scenario='background-finalization-only',cells=[dict(id='A')])):
            with self.assertRaisesRegex(Rejected,'not a release pair'):runtime.compare(Path('/unused'))
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'plan.json').write_text('{}');(root/'review.json').write_text('{}')
            (root/'cells').mkdir();(root/'native-admission.json').write_text(json.dumps(dict(
                plan_sha256=runtime.shared.sha(root/'plan.json'),review_sha256=runtime.shared.sha(root/'review.json'),device='device')))
            with self.assertRaises(Rejected):runtime.admit(root,'B',dict(cells=[dict(id='A')],device='device'))

    def test_build_option_does_not_change_default_helpers_and_rejects_non_boolean(self):
        ordinary=build.helpers(True);final=build.helpers(True,True)
        self.assertEqual({k:v for k,v in final.items() if k in ordinary},ordinary)
        self.assertEqual(set(final)-set(ordinary),{'tools/multi-scene/interactive-transitions/'+n for n in
            ['physical_background.py','test_physical_background.py']})
        for value in [None,1,'true']:
            with self.assertRaises(Rejected):build.prepare(Path('/unused-physical-finalization'),background_finalization=value)

    def test_compiled_lease_ends_exactly_once_and_rejects_expired_denied_foreign_and_late_callbacks(self):
        parent=os.environ.get('EXP223_FINALIZATION_CONTROL_ROOT')
        folder=Path(tempfile.mkdtemp(prefix='swift-lease-',dir=parent))
        stub='''import Foundation
struct UIBackgroundTaskIdentifier: Equatable { let rawValue: Int; static let invalid = Self(rawValue: -1) }
@MainActor class UIApplication {
    static let shared = UIApplication()
    func beginBackgroundTask(withName: String, expirationHandler: @escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ task: UIBackgroundTaskIdentifier) {}
}
enum Settings { static let runID = "host-controls" }
'''
        control=r'''
@main struct Controls {
    @MainActor static func main() {
        for scenario in ["success", "expired", "timeout", "write-failed", "denied", "late", "reentrant-expiry"] {
            var clock: TimeInterval = 100
            var expiration: (@MainActor @Sendable () -> Void)?
            var timeout: (@MainActor @Sendable () -> Void)?
            var ended: [Int] = []
            var records: [[String: Any]] = []
            var order: [String] = []
            let lease = PhysicalBackgroundFinalization(
                beginTask: { callback in
                    expiration = callback; order.append("begin")
                    if scenario == "reentrant-expiry" { callback() }
                    return scenario == "denied" ? .invalid : UIBackgroundTaskIdentifier(rawValue: 7)
                },
                endTask: { ended.append($0.rawValue); order.append("end") },
                now: { clock }, scheduleTimeout: { timeout = $0 },
                persist: { _, record in records.append(record); order.append("persist") })
            let token = lease.begin(checkpoint: "background-10")
            if let token = token {
                precondition(lease.begin(checkpoint: "other") == nil)
                lease.finish(token: "foreign", success: true, reason: "writer_completed")
                precondition(records.isEmpty && ended.isEmpty)
                clock = scenario == "late" ? 106 : 101.2
                if scenario == "expired" { expiration?() }
                else if scenario == "timeout" { timeout?() }
                else { lease.finish(token: token, success: scenario != "write-failed", reason: "writer_completed") }
                lease.finish(token: token, success: true, reason: "writer_completed")
                expiration?(); timeout?()
            }
            precondition(records.count == 1)
            precondition(records[0]["state"] as? String == (scenario == "success" ? "PASS" : "INVALID"))
            precondition(ended == (scenario == "denied" ? [] : [7]))
            if scenario == "success" {
                precondition(order == ["begin", "end", "persist"])
                let data = try! JSONSerialization.data(withJSONObject: records[0], options: [.sortedKeys])
                print(String(data: data, encoding: .utf8)!)
            }
            print(scenario + ":PASS")
        }
    }
}
'''
        (folder/'Control.swift').write_text(stub+background.SWIFT+control)
        env=build.shared.environment()
        result=subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library',str(folder/'Control.swift'),
            '-o',str(folder/'control')],capture_output=True,env=env,timeout=45)
        (folder/'compile.log').write_bytes(result.stdout+result.stderr)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        result=subprocess.run([str(folder/'control')],capture_output=True,timeout=10)
        (folder/'run.log').write_bytes(result.stdout+result.stderr)
        self.assertEqual(result.returncode,0,result.stderr.decode())
        lines=result.stdout.splitlines()
        self.assertEqual(len(lines),8)
        record=json.loads(lines[0]);self.assertEqual(record['token'],record['token'].upper())
        original=json.dumps(record)
        self.assertIs(background.validate_receipt(record,run_id='host-controls',pid=record['pid'],
            checkpoint='background-10'),record)
        self.assertEqual(json.dumps(record),original)


if __name__=='__main__':unittest.main()

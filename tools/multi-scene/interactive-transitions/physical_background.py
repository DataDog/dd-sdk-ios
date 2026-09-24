"""Physical fixture finalization; no SDK mutation or relaxed evidence predicate."""
import hashlib
from pathlib import Path
from acceptance_common import require

SWIFT = r'''
@MainActor final class PhysicalBackgroundFinalization {
    static let shared = PhysicalBackgroundFinalization()
    private struct Pending {
        let token: String
        let checkpoint: String
        let started: TimeInterval
        var task: UIBackgroundTaskIdentifier
    }
    private var pending: Pending?
    private let beginTask: (@escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    private let endTask: (UIBackgroundTaskIdentifier) -> Void
    private let now: () -> TimeInterval
    private let scheduleTimeout: (@escaping @MainActor @Sendable () -> Void) -> Void
    private let persist: (String, [String: Any]) -> Void

    init(
        beginTask: ((@escaping @MainActor @Sendable () -> Void) -> UIBackgroundTaskIdentifier)? = nil,
        endTask: ((UIBackgroundTaskIdentifier) -> Void)? = nil,
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        scheduleTimeout: ((@escaping @MainActor @Sendable () -> Void) -> Void)? = nil,
        persist: @escaping (String, [String: Any]) -> Void = { identifier, receipt in
            let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("background-finalization-" + identifier + ".json")
            do {
                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: path, options: .atomic)
            } catch { print("Physical finalization receipt failed") }
        }
    ) {
        self.beginTask = beginTask ?? {
            UIApplication.shared.beginBackgroundTask(withName: "Fixture evidence finalization", expirationHandler: $0)
        }
        self.endTask = endTask ?? { UIApplication.shared.endBackgroundTask($0) }
        self.now = now
        self.scheduleTimeout = scheduleTimeout ?? { callback in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { callback() }
        }
        self.persist = persist
    }

    func begin(checkpoint: String) -> String? {
        guard pending == nil else { return nil }
        let token = UUID().uuidString
        pending = Pending(token: token, checkpoint: checkpoint, started: now(), task: .invalid)
        let task = beginTask { [weak self] in self?.finish(token: token, success: false, reason: "expired") }
        // A reentrant expiry can clear the pending operation before UIKit returns its ID.
        guard pending?.token == token else {
            if task != .invalid { endTask(task) }
            return nil
        }
        pending?.task = task
        guard task != .invalid else {
            finish(token: token, success: false, reason: "denied")
            return nil
        }
        scheduleTimeout { [weak self] in self?.finish(token: token, success: false, reason: "deadline") }
        return token
    }

    func finish(token: String, success: Bool, reason: String) {
        guard let operation = pending, operation.token == token else { return }
        pending = nil
        let finished = now()
        let bounded = finished >= operation.started && finished < operation.started + 5
        if operation.task != .invalid { endTask(operation.task) }
        persist(operation.checkpoint, [
            "schema_version": 1, "run_id": Settings.runID,
            "pid": ProcessInfo.processInfo.processIdentifier, "token": operation.token,
            "checkpoint": operation.checkpoint, "started_uptime": operation.started,
            "deadline_uptime": operation.started + 5, "finished_uptime": finished,
            "task_ended": operation.task != .invalid,
            "state": success && bounded && operation.task != .invalid ? "PASS" : "INVALID",
            "reason": bounded ? reason : "deadline"
        ])
    }
}
'''


def render(source, expected_sha256):
    require(hashlib.sha256(source).hexdigest() == expected_sha256, 'background source changed')
    text = source.decode()
    def replace(old, new):
        nonlocal text
        require(text.count(old) == 1, 'ambiguous physical background source anchor')
        text = text.replace(old, new)
    replace('''        if kind == "native_background" {
            let identifier = "background-" + String(sequence)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) { [self] in checkpoint(identifier) }
        }
''', '')
    replace('func checkpoint(_ identifier: String) {', 'func checkpoint(_ identifier: String, completion: ((Bool) -> Void)? = nil) {')
    replace('''        writer.async { [self] in
            do {
                let bytes = try Data(contentsOf: output)''', '''        writer.async { [self] in
            var succeeded = false
            defer { completion?(succeeded) }
            do {
                let bytes = try Data(contentsOf: output)''')
    replace('''                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: destination, options: .atomic)
            } catch''', '''                try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]).write(to: destination, options: .atomic)
                succeeded = !writeFailed
            } catch''')
    replace('''            ObservationStore.shared.append("native_background", [:])
            Task { @MainActor in TransitionObservation.shared.close(reason: "background"); captureGeometry() }''', '''            guard Thread.isMainThread else {
                ObservationStore.shared.append("human_failure", ["reason": "background notification is not on main"])
                return
            }
            MainActor.assumeIsolated {
                let sequence = ObservationStore.shared.append("native_background", [:])
                let identifier = "background-" + String(sequence)
                let token = PhysicalBackgroundFinalization.shared.begin(checkpoint: identifier)
                TransitionObservation.shared.close(reason: "background")
                captureGeometry()
                guard let token = token else { return }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) {
                    ObservationStore.shared.checkpoint(identifier) { success in
                        DispatchQueue.main.async {
                            PhysicalBackgroundFinalization.shared.finish(token: token, success: success, reason: "writer_completed")
                        }
                    }
                }
            }''')
    return (text + '\n' + SWIFT).encode()


def validate_receipt(receipt, *, run_id, pid, checkpoint):
    import math
    import re
    import uuid
    fields = {'schema_version','run_id','pid','token','checkpoint','started_uptime',
              'deadline_uptime','finished_uptime','task_ended','state','reason'}
    require(set(receipt) == fields and type(receipt['schema_version']) is int and receipt['schema_version'] == 1,
            'incomplete physical finalization receipt')
    token = receipt['token']
    require(type(token) is str and re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', token)
            and str(uuid.UUID(token)) == token.casefold(), 'malformed physical finalization token')
    require(receipt['run_id'] == run_id and type(receipt['pid']) is int and receipt['pid'] == pid and
            receipt['checkpoint'] == checkpoint,
            'foreign physical finalization receipt')
    values = [receipt[k] for k in ['started_uptime','deadline_uptime','finished_uptime']]
    require(all(type(v) in [int,float] and math.isfinite(v) for v in values), 'malformed physical finalization clock')
    start, deadline, finish = values
    require(start > 0 and deadline == start + 5 and start <= finish < deadline and
            receipt['task_ended'] is True and receipt['state'] == 'PASS' and receipt['reason'] == 'writer_completed',
            'physical finalization expired, failed or retained its lease')
    return receipt

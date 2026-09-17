/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
#if DEBUG
@_spi(Experimental)
@_spi(objc)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

enum ProbeErrorAcceptance {
    #if DEBUG
    @MainActor private static var running = false
    @MainActor private static var callbacks = 0

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else { return .rejected(reason: "Error batch already started") }
        running = true
        Task { @MainActor in
            do {
                try await run()
                record(ProbeErrorContract.completed)
            } catch {
                record(ProbeErrorContract.completed, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    private enum FixtureError: Error { case missing(String) }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError.missing(message) }
    }

    private static func record(
        _ name: String, context: RUMCoreContext? = nil,
        result: ProbeSemanticResultState = .pass, reason: String? = nil
    ) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: context == nil ? .probe : .internalHook,
            rumContext: context.map {
                ProbeRUMContext(sessionID: $0.sessionID, viewID: $0.viewID, viewName: $0.viewName, viewURL: $0.viewPath)
            },
            name: name, result: result, reason: reason
        ))
    }

    // Check only this fixture's synthetic payload without recording messages or stacks.
    static func recordPayloadCheck(_ event: RUMErrorEvent) {
        let phase: String? = event.context?.contextInfo[ProbeRuntime.Attribute.phase]?.dd.decode()
        let run: String? = event.context?.contextInfo[ProbeRuntime.Attribute.runID]?.dd.decode()
        guard let phase, ProbeErrorContract.phases.contains(phase) else {
            record("error-unexpected-payload", result: .fail)
            return
        }
        let isResource = phase == ProbeErrorContract.resource
        let expectedType: String? = phase == ProbeErrorContract.phases[0] ? "ProbeMessage"
            : phase == ProbeErrorContract.phases[3] ? nil : isResource ? "ProbeResource" : "ProbeCurrentError - 177"
        let stackMatches = phase == ProbeErrorContract.phases[0] ? event.error.stack == "Exp177.swift:177"
            : phase == ProbeErrorContract.phases[3] ? event.error.stack == "exp177 stack" : true
        let matches = run == ProbeRuntime.runID && event.error.message == phase && event.error.type == expectedType
            && event.error.source.rawValue == (isResource ? "network" : "custom") && stackMatches
        record("error-payload-" + phase, result: matches ? .pass : .fail)
    }

    @MainActor
    private static func scene(_ label: String) throws -> UIWindowScene {
        guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: label),
              let scene = ProbeRuntime.sceneRegistry.window(for: handle)?.windowScene else {
            throw FixtureError.missing("native scene " + label)
        }
        return scene
    }

    @MainActor
    private static func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing("mapper/callback deadline")
    }

    @MainActor
    private static func run() async throws {
        guard #available(iOS 27.0, *) else { throw FixtureError.missing("iOS27 targets") }
        let a = try scene("scene-A")
        let b = try scene("scene-B")
        try require(a !== b, "distinct native scenes")
        let aID = RUMSceneIdentifier(rawValue: a.session.persistentIdentifier)
        let bID = RUMSceneIdentifier(rawValue: b.session.persistentIdentifier)
        guard let monitor = RUMMonitor.shared() as? Monitor,
              let ownerA = monitor.rumContextSnapshot(for: .scene(aID)),
              let ownerB = monitor.rumContextSnapshot(for: .scene(bID)) else {
            throw FixtureError.missing("both current SDK owners")
        }
        try require(ownerA.viewID != ownerB.viewID && ownerA.sessionID == ownerB.sessionID, "distinct owners in one session")
        record("error-owner-a", context: ownerA)
        record("error-owner-b", context: ownerB)
        let targetA = RUMViewTarget.current(in: a)
        let targetB = RUMViewTarget.current(in: b)
        let objcTarget = objc_RUMViewTarget.current(in: a)
        let objc = objc_RUMMonitor(swiftRUMMonitor: monitor)
        func attributes(_ phase: String, source: String = "scene-A") -> [String: Encodable] {
            [
                ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                ProbeRuntime.Attribute.sourceScene: source,
                ProbeRuntime.Attribute.screen: "home",
                ProbeRuntime.Attribute.phase: phase,
            ]
        }
        func error(_ phase: String) -> Error {
            NSError(domain: "ProbeCurrentError", code: 177, userInfo: [NSLocalizedDescriptionKey: phase])
        }
        // Enqueue the whole critical batch without awaiting a lifecycle transition.
        record("error-call-boundary")
        monitor.startAction(type: .tap, name: ProbeErrorContract.actionA, view: targetA, attributes: attributes(ProbeErrorContract.actionA))
        monitor.startAction(type: .tap, name: ProbeErrorContract.actionB, view: targetB, attributes: attributes(ProbeErrorContract.actionB, source: "scene-B"))
        let phases = ProbeErrorContract.phases
        let key = ProbeRuntime.runID + "-captured-error"
        let resourceURL = URL(string: "https://error-probe.invalid/" + ProbeRuntime.runID + "/" + ProbeErrorContract.resource)!
        monitor.startResource(resourceKey: key, url: resourceURL, view: targetA, attributes: attributes(ProbeErrorContract.resource))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: bID.rawValue) {
            monitor.addError(message: phases[0], type: "ProbeMessage", view: targetA, attributes: attributes(phases[0]), file: "Probe/Exp177.swift", line: 177)
            monitor.addError(error: error(phases[1]), view: targetA, attributes: attributes(phases[1]))
            monitor.addError(error: error(phases[2]), view: targetA, attributes: attributes(phases[2])) {
                Task { @MainActor in
                    callbacks += 1
                    record("error-callback-completed")
                }
            }
            objc.addError(message: phases[3], stack: "exp177 stack", source: .custom, view: objcTarget, attributes: attributes(phases[3]))
            objc.addError(error: error(phases[4]), source: .custom, view: objcTarget, attributes: attributes(phases[4]))
        }
        let unavailable = RUMCommandTarget.scene(RUMSceneIdentifier(rawValue: "never-tracked-" + ProbeRuntime.runID))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerA, sceneIdentifier: bID.rawValue) {
            monitor.addError(error: error(phases[5]), source: .custom, attributes: attributes(phases[5]), explicitTarget: unavailable)
        }
        monitor.addError(error: error(phases[6]), source: .custom, attributes: attributes(phases[6]), explicitTarget: unavailable)
        monitor.addError(error: error(phases[7]), attributes: attributes(phases[7]))
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: bID.rawValue) {
            monitor.stopResourceWithError(resourceKey: key, message: ProbeErrorContract.resource, type: "ProbeResource", attributes: attributes(ProbeErrorContract.resource))
        }
        monitor.stopAction(type: .tap, name: nil, view: targetA, attributes: attributes(ProbeErrorContract.actionA))
        monitor.stopAction(type: .tap, name: nil, view: targetB, attributes: attributes(ProbeErrorContract.actionB, source: "scene-B"))
        record("error-calls-enqueued")
        try await waitFor {
            let signals = ProbeRuntime.eventRecorder.snapshot()
            return callbacks >= 1 && signals.filter { $0.kind == .rumError }.count >= 9
                && signals.filter { $0.kind == .rumAction && [ProbeErrorContract.actionA, ProbeErrorContract.actionB].contains($0.name ?? "") }.count == 2
        }
        let signals = ProbeRuntime.eventRecorder.snapshot()
        let errors = signals.filter { $0.kind == .rumError }
        let actions = signals.filter { $0.kind == .rumAction }
        try require(callbacks == 1 && errors.count == 9 && signals.filter { $0.kind == .rumResource }.isEmpty, "complete error inventory and one callback")
        for (name, owner, count) in [(ProbeErrorContract.actionA, ownerA, 7), (ProbeErrorContract.actionB, ownerB, 2)] {
            let matched = actions.filter { $0.name == name }
            try require(matched.count == 1, "one named action")
            let action = matched[0]
            try require(action.rumContext?.viewID == owner.viewID && action.rumContext?.sessionID == owner.sessionID
                        && action.action?.errorCount == Int64(count) && action.action?.resourceCount == 0, "action owner/counts")
            for phase in phases where (ProbeErrorContract.peerPhases.contains(phase) ? name == ProbeErrorContract.actionB : name == ProbeErrorContract.actionA) {
                let matchedErrors = errors.filter { $0.name == phase }
                try require(matchedErrors.count == 1, "one error " + phase)
                let event = matchedErrors[0]
                try require(event.rumContext?.viewID == owner.viewID && event.rumContext?.sessionID == owner.sessionID
                            && event.rumContext?.actionIDs == [action.action?.id].compactMap { $0 }, "exact error/action owner " + phase)
            }
        }
        try require(signals.filter { $0.name?.hasPrefix("error-payload-") == true && $0.result == .pass }.count == 9, "nine synthetic payload checks")
        record("error-local-owners-verified")
    }
    #endif
}

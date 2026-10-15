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

enum ProbeTimingAcceptance {
    #if DEBUG
    @MainActor private static var running = false

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else { return .rejected(reason: "Timing batch already started") }
        running = true
        Task { @MainActor in
            do {
                try await run()
                record(ProbeTimingContract.completed)
            } catch {
                record(ProbeTimingContract.completed, result: .fail, reason: String(describing: error))
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

    static func recordPayloadCheck(_ event: RUMErrorEvent) {
        let context = event.context?.contextInfo ?? [:]
        let phase: String? = context[ProbeRuntime.Attribute.phase]?.dd.decode()
        let run: String? = context[ProbeRuntime.Attribute.runID]?.dd.decode()
        guard let phase, ProbeTimingContract.phases.contains(phase),
              let snapshot = ProbeRuntime.eventRecorder.snapshot().last(where: {
                  $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == event.view.id
                      && $0.rumContext?.sessionID == event.session.id
              }), let state = snapshot.timingState else {
            record("timing-missing-view-state", result: .fail)
            return
        }
        let matches = run == ProbeRuntime.runID && event.error.message == phase
            && event.error.type == "ProbeTiming" && event.error.source.rawValue == "custom"
            && snapshot.rumContext?.viewActive == true
            && Set(state.timings.keys).isSubset(of: Set(ProbeTimingContract.keys))
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion, evidenceSource: .rumMapper, rumContext: snapshot.rumContext,
            acknowledgedSignalSequence: snapshot.sequence, eventID: event.error.id,
            name: "timing-payload-" + phase, timingState: matches ? state : nil,
            result: matches ? .pass : .fail
        ))
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
        record("timing-owner-a", context: ownerA)
        record("timing-owner-b", context: ownerB)
        let targetA = RUMViewTarget.current(in: a)
        let targetB = RUMViewTarget.current(in: b)
        guard let objcTarget = objc_RUMViewTarget.current(in: b) else {
            throw FixtureError.missing("main-thread Objective-C target")
        }
        let objc = objc_RUMMonitor(swiftRUMMonitor: monitor)
        func checkpoint(_ index: Int) {
            for (offset, target) in [(0, targetA), (1, targetB)] {
                let phase = ProbeTimingContract.phases[index * 2 + offset]
                monitor.addError(message: phase, type: "ProbeTiming", view: target, attributes: [
                    ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                    ProbeRuntime.Attribute.sourceScene: "scene-A",
                    ProbeRuntime.Attribute.screen: "home",
                    ProbeRuntime.Attribute.phase: phase,
                ])
            }
        }
        // Keep all public mutations and their markers before the first lifecycle await.
        record("timing-call-boundary")
        checkpoint(0)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: bID.rawValue) {
            monitor.addTiming(name: ProbeTimingContract.shared, view: targetA)
            monitor.addViewLoadingTime(overwrite: false, view: targetA)
            checkpoint(1)
            monitor.addTiming(name: ProbeTimingContract.shared, view: targetA)
            monitor.addViewLoadingTime(overwrite: false, view: targetA)
            checkpoint(2)
            monitor.addViewLoadingTime(overwrite: true, view: targetA)
            checkpoint(3)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerA, sceneIdentifier: aID.rawValue) {
            objc.addTiming(name: ProbeTimingContract.shared, view: objcTarget)
            objc.addViewLoadingTime(overwrite: false, view: objcTarget)
            checkpoint(4)
            objc.addTiming(name: ProbeTimingContract.shared, view: objcTarget)
            objc.addViewLoadingTime(overwrite: false, view: objcTarget)
            checkpoint(5)
            objc.addViewLoadingTime(overwrite: true, view: objcTarget)
            checkpoint(6)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: bID.rawValue) {
            monitor.addTiming(name: ProbeTimingContract.finalA, view: targetA)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerA, sceneIdentifier: aID.rawValue) {
            objc.addTiming(name: ProbeTimingContract.finalB, view: objcTarget)
        }
        checkpoint(7)
        record("timing-calls-enqueued")
        for _ in 0..<250 {
            if ProbeRuntime.eventRecorder.snapshot().filter({ $0.kind == .rumError }).count >= 16 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let signals = ProbeRuntime.eventRecorder.snapshot()
        let errors = signals.filter { $0.kind == .rumError }
        try require(errors.count == 16 && signals.filter { $0.kind == .rumResource }.isEmpty, "complete error inventory")
        for (index, phase) in ProbeTimingContract.phases.enumerated() {
            let owner = index.isMultiple(of: 2) ? ownerA : ownerB
            let events = errors.filter { $0.name == phase }
            try require(events.count == 1, "one marker " + phase)
            try require(events[0].rumContext?.viewID == owner.viewID && events[0].rumContext?.sessionID == owner.sessionID,
                        "exact marker owner " + phase)
        }
        try require(signals.filter { $0.name?.hasPrefix("timing-payload-") == true && $0.result == .pass }.count == 16,
                    "sixteen bound timing payloads")
        record("timing-local-owners-verified")
    }
    #endif
}

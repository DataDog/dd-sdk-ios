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

enum ProbeAttributeAcceptance {
    #if DEBUG
    @MainActor private static var running = false

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else { return .rejected(reason: "Attribute batch already started") }
        running = true
        Task { @MainActor in
            do {
                try await run()
                record(ProbeAttributeContract.completed)
            } catch {
                record(ProbeAttributeContract.completed, result: .fail, reason: String(describing: error))
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

    // Only fixed synthetic keys and validated values can enter the exported evidence.
    static func recordPayloadCheck(_ event: RUMErrorEvent) {
        let context = event.context?.contextInfo ?? [:]
        let phase: String? = context[ProbeRuntime.Attribute.phase]?.dd.decode()
        let run: String? = context[ProbeRuntime.Attribute.runID]?.dd.decode()
        guard let phase, let index = ProbeAttributeContract.phases.firstIndex(of: phase) else {
            record("attribute-unexpected-payload", result: .fail)
            return
        }
        let expected = ProbeAttributeState.expected(checkpoint: index / 2, isA: index.isMultiple(of: 2))
        let selected = context.filter { $0.key.hasPrefix("exp178_") }
        let data = try? JSONEncoder().encode(AnyEncodable(selected))
        let actual = data.flatMap { try? JSONDecoder().decode(ProbeAttributeState.self, from: $0) }
        let matches = run == ProbeRuntime.runID && event.error.message == phase
            && event.error.type == "ProbeAttribute" && event.error.source.rawValue == "custom"
            && actual == expected && Set(selected.keys) == expected.keys
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion, evidenceSource: .rumMapper,
            rumContext: ProbeRUMContext(sessionID: event.session.id, viewID: event.view.id),
            eventID: event.error.id, name: "attribute-payload-" + phase,
            attributeState: matches ? actual : nil, result: matches ? .pass : .fail
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
        record("attribute-owner-a", context: ownerA)
        record("attribute-owner-b", context: ownerB)
        let targetA = RUMViewTarget.current(in: a)
        let targetB = RUMViewTarget.current(in: b)
        guard let objcTarget = objc_RUMViewTarget.current(in: b) else {
            throw FixtureError.missing("main-thread Objective-C target")
        }
        let objc = objc_RUMMonitor(swiftRUMMonitor: monitor)
        func checkpoint(_ index: Int) {
            for (offset, target) in [(0, targetA), (1, targetB)] {
                let phase = ProbeAttributeContract.phases[index * 2 + offset]
                monitor.addError(message: phase, type: "ProbeAttribute", view: target, attributes: [
                    ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                    ProbeRuntime.Attribute.sourceScene: "scene-A",
                    ProbeRuntime.Attribute.screen: "home",
                    ProbeRuntime.Attribute.phase: phase,
                ])
            }
        }
        // Keep all eight public calls and their markers before the first lifecycle await.
        record("attribute-call-boundary")
        monitor.addAttribute(forKey: "exp178_shadow", value: "global-v1")
        monitor.addAttribute(forKey: "exp178_process", value: "global-v1")
        checkpoint(0)
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerB, sceneIdentifier: bID.rawValue) {
            monitor.addViewAttribute(forKey: "exp178_shadow", value: "swift-a", view: targetA)
            checkpoint(1)
            monitor.addViewAttributes(["exp178_integer": 7, "exp178_flag": true, "exp178_nested": ["value": "swift-a"]], view: targetA)
            checkpoint(2)
            monitor.removeViewAttribute(forKey: "exp178_shadow", view: targetA)
            checkpoint(3)
            monitor.removeViewAttributes(forKeys: ["exp178_integer", "exp178_flag", "exp178_nested"], view: targetA)
            checkpoint(4)
        }
        RUMContextHandoff.withValue(owner: monitor.rumContextHandoffOwner, rumContext: ownerA, sceneIdentifier: aID.rawValue) {
            objc.addViewAttribute(forKey: "exp178_shadow", value: "objc-b", view: objcTarget)
            checkpoint(5)
            objc.addViewAttributes(["exp178_integer": 7, "exp178_flag": true, "exp178_nested": ["value": "objc-b"]], view: objcTarget)
            checkpoint(6)
            objc.removeViewAttribute(forKey: "exp178_shadow", view: objcTarget)
            checkpoint(7)
            objc.removeViewAttributes(forKeys: ["exp178_integer", "exp178_flag", "exp178_nested"], view: objcTarget)
            checkpoint(8)
        }
        monitor.addAttribute(forKey: "exp178_shadow", value: "global-v2")
        monitor.addAttribute(forKey: "exp178_process", value: "global-v2")
        checkpoint(9)
        record("attribute-calls-enqueued")
        for _ in 0..<250 {
            if ProbeRuntime.eventRecorder.snapshot().filter({ $0.kind == .rumError }).count >= 20 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let signals = ProbeRuntime.eventRecorder.snapshot()
        let errors = signals.filter { $0.kind == .rumError }
        try require(errors.count == 20 && signals.filter { $0.kind == .rumResource }.isEmpty, "complete error inventory")
        for (index, phase) in ProbeAttributeContract.phases.enumerated() {
            let owner = index.isMultiple(of: 2) ? ownerA : ownerB
            let events = errors.filter { $0.name == phase }
            try require(events.count == 1, "one marker " + phase)
            try require(events[0].rumContext?.viewID == owner.viewID && events[0].rumContext?.sessionID == owner.sessionID,
                        "exact marker owner " + phase)
        }
        try require(signals.filter { $0.name?.hasPrefix("attribute-payload-") == true && $0.result == .pass }.count == 20,
                    "twenty typed attribute payloads")
        record("attribute-local-owners-verified")
    }
    #endif
}

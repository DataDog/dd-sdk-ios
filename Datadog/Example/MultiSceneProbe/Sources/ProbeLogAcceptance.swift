/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogLogs
#if DEBUG
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

enum ProbeLogAcceptance {
    #if DEBUG
    @MainActor private static var running = false

    static func configure() {
        Logs.enable(with: .init(eventMapper: { event in
            guard let data = try? JSONEncoder().encode(event),
                  let wire = ProbeLogWireIdentity.decode(data),
                  wire.runID == ProbeRuntime.runID else {
                record("log-invalid-payload", result: .fail)
                return event
            }
            ProbeRuntime.eventRecorder.record(ProbeSignal(
                kind: .rumLog,
                evidenceSource: .logMapper,
                sourceContext: ProbeSourceContext(logicalSceneID: wire.source, screen: "home", phase: wire.phase),
                rumContext: ProbeRUMContext(sessionID: wire.sessionID, viewID: wire.viewID, actionIDs: [wire.actionID]),
                name: wire.phase,
                log: wire
            ))
            return event
        }))
    }

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else {
            return .rejected(reason: "Log batch already started")
        }
        running = true
        Task.detached { @MainActor in
            do {
                try await run()
                record(ProbeLogContract.completed)
            } catch {
                record(ProbeLogContract.completed, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    private enum FixtureError: Error { case missing(String) }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw FixtureError.missing(message) }
    }

    private static func record(
        _ name: String,
        context: RUMCoreContext? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: context == nil ? .probe : .internalHook,
            rumContext: context.map {
                ProbeRUMContext(
                    sessionID: $0.sessionID,
                    viewID: $0.viewID,
                    viewName: $0.viewName,
                    viewURL: $0.viewPath,
                    actionIDs: $0.userActionID.map { [$0] }
                )
            },
            name: name,
            result: result,
            reason: reason
        ))
    }

    static func recordPayloadCheck(_ event: RUMErrorEvent) {
        let values = event.context?.contextInfo ?? [:]
        let phase: String? = values[ProbeRuntime.Attribute.phase]?.dd.decode()
        let run: String? = values[ProbeRuntime.Attribute.runID]?.dd.decode()
        guard let phase, ProbeLogContract.errorPhases.contains(phase) else {
            record("log-unexpected-mirror", result: .fail)
            return
        }
        let valid = run == ProbeRuntime.runID && event.error.message == phase
            && event.error.source == .logger && event.error.isCrash != true
            && !values.keys.contains { $0.hasPrefix("_dd.internal.rum.error.") }
        record("log-mirror-payload-" + phase, result: valid ? .pass : .fail)
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
    private static func waitFor(_ predicate: () -> Bool, _ message: String) async throws {
        for _ in 0..<250 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing(message)
    }

    @MainActor
    private static func run() async throws {
        guard #available(iOS 27.0, *), let monitor = RUMMonitor.shared() as? Monitor else {
            throw FixtureError.missing("live monitor")
        }
        let a = try scene("scene-A")
        let b = try scene("scene-B")
        try require(a !== b, "distinct native scenes")
        let aID = a.session.persistentIdentifier
        let bID = b.session.persistentIdentifier
        let targetA = RUMViewTarget.current(in: a)
        let targetB = RUMViewTarget.current(in: b)
        func attributes(_ phase: String, source: String) -> [String: Encodable] {
            [
                ProbeRuntime.Attribute.runID: ProbeRuntime.runID,
                ProbeRuntime.Attribute.sourceScene: source,
                ProbeRuntime.Attribute.screen: "home",
                ProbeRuntime.Attribute.phase: phase,
            ]
        }
        let logger = DatadogLogs.Logger.create(with: .init(
            service: ProbeRuntime.serviceName,
            name: "multi-scene-acceptance",
            bundleWithRumEnabled: true,
            bundleWithTraceEnabled: false
        ))
        record("log-actions-boundary")
        monitor.startAction(
            type: .tap,
            name: ProbeLogContract.actionA,
            view: targetA,
            attributes: attributes(ProbeLogContract.actionA, source: "scene-A")
        )
        monitor.startAction(
            type: .tap,
            name: ProbeLogContract.actionB,
            view: targetB,
            attributes: attributes(ProbeLogContract.actionB, source: "scene-B")
        )
        try await waitFor({
            monitor.rumContextSnapshot(for: .scene(.init(rawValue: aID)))?.userActionID != nil
                && monitor.rumContextSnapshot(for: .scene(.init(rawValue: bID)))?.userActionID != nil
        }, "both live actions")
        guard let ownerA = monitor.rumContextSnapshot(for: .scene(.init(rawValue: aID))),
              let ownerB = monitor.rumContextSnapshot(for: .scene(.init(rawValue: bID))) else {
            throw FixtureError.missing("both current SDK owners")
        }
        try require(ownerA.viewID != ownerB.viewID && ownerA.sessionID == ownerB.sessionID
                    && ownerA.userActionID != ownerB.userActionID, "distinct live owners and actions")
        record("log-owner-a", context: ownerA)
        record("log-owner-b", context: ownerB)
        guard let representative = monitor.rumContextSnapshot(for: .processRepresentative) else {
            throw FixtureError.missing("process representative")
        }
        try require(
            representative.viewID == ownerB.viewID && representative.userActionID == ownerB.userActionID,
            "B represents before A emission"
        )
        record("log-representative-before-a", context: representative)
        record("log-call-boundary")
        let handoffOwner = monitor.rumContextHandoffOwner
        func emit(_ suffix: String) {
            let source = ProbeLogContract.source(for: "log-info-" + suffix)
            logger.info("log-info-" + suffix, attributes: attributes("log-info-" + suffix, source: source))
            logger.error("log-error-" + suffix, attributes: attributes("log-error-" + suffix, source: source))
        }
        for (suffix, context, nativeID) in [("a", ownerA, aID), ("b", ownerB, bID)] {
            RUMContextHandoff.withValue(owner: handoffOwner, rumContext: context, sceneIdentifier: nativeID) {
                record("log-emission-" + suffix, context: context)
                emit(suffix)
            }
            try await waitFor({
                ProbeRuntime.eventRecorder.snapshot().contains {
                    $0.kind == .rumError && $0.name == "mirror-log-error-" + suffix
                }
            }, "mirror " + suffix)
        }
        try require(RUMContextHandoff.current(for: handoffOwner) == nil, "source-less emission inherited handoff")
        guard let fallback = monitor.rumContextSnapshot(for: .processRepresentative),
              fallback.viewID == ownerA.viewID || fallback.viewID == ownerB.viewID else {
            throw FixtureError.missing("independent source-less representative")
        }
        record("log-fallback-empty-handoff")
        record("log-emission-fallback", context: fallback)
        emit("fallback")
        try await waitFor({
            ProbeRuntime.eventRecorder.snapshot().contains {
                $0.kind == .rumError && $0.name == "mirror-log-error-fallback"
            }
        }, "source-less mirror")
        record("log-stops-boundary")
        monitor.stopAction(
            type: .tap,
            name: nil,
            view: targetA,
            attributes: attributes(ProbeLogContract.actionA, source: "scene-A")
        )
        monitor.stopAction(
            type: .tap,
            name: nil,
            view: targetB,
            attributes: attributes(ProbeLogContract.actionB, source: "scene-B")
        )
        try await waitFor({
            ProbeRuntime.eventRecorder.snapshot().filter { $0.kind == .rumAction }.count == 2
        }, "both final action records")
        let signals = ProbeRuntime.eventRecorder.snapshot()
        let events = signals.filter { [.rumLog, .rumError, .rumAction].contains($0.kind) }
        try require(events.compactMap(\.name) == ProbeLogContract.inventory, "exact log/mirror/action inventory")
        for event in events where event.kind != .rumAction {
            let name = event.name ?? ""
            let expected = name.hasSuffix("-a") ? ownerA : name.hasSuffix("-b") ? ownerB : fallback
            try require(
                event.rumContext?.viewID == expected.viewID && event.rumContext?.sessionID == expected.sessionID
                    && event.rumContext?.actionIDs == [expected.userActionID].compactMap { $0 },
                "captured event owner " + name
            )
            if let log = event.log {
                try require(
                    log.applicationID == expected.applicationID && log.service == ProbeRuntime.serviceName,
                    "encoded application/service"
                )
            }
        }
        for (name, context) in [(ProbeLogContract.actionA, ownerA), (ProbeLogContract.actionB, ownerB)] {
            guard let action = events.first(where: { $0.kind == .rumAction && $0.name == name }) else {
                throw FixtureError.missing("final action " + name)
            }
            let expectedCount: Int64 = fallback.viewID == context.viewID ? 2 : 1
            try require(action.action?.id == context.userActionID && action.rumContext?.viewID == context.viewID
                        && action.rumContext?.sessionID == context.sessionID && action.action?.errorCount == expectedCount
                        && action.action?.resourceCount == 0, "independent action ownership/counts")
        }
        try require(
            signals.filter { $0.name?.hasPrefix("log-mirror-payload-") == true && $0.result == .pass }.count == 3,
            "three sanitized mirror payloads"
        )
        try require(!signals.contains { [.rumResource, .rumTrace].contains($0.kind) }, "unexpected Resource/Trace")
        record("log-local-owners-verified")
    }
    #endif
}

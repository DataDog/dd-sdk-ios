/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogTrace
#if DEBUG
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

enum ProbeTraceAcceptance {
    #if DEBUG
    @MainActor private static var running = false

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else {
            return .rejected(reason: "Trace batch already started")
        }
        running = true
        // Source-less starts must not inherit the observable driver's task handoff.
        Task.detached { @MainActor in
            do {
                try await run()
                record(ProbeTraceContract.completed)
            } catch {
                record(ProbeTraceContract.completed, result: .fail, reason: String(describing: error))
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
                ProbeRUMContext(sessionID: $0.sessionID, viewID: $0.viewID, viewName: $0.viewName, viewURL: $0.viewPath)
            },
            name: name,
            result: result,
            reason: reason
        ))
    }

    static func signal(_ event: SpanEvent) -> ProbeSignal? {
        guard event.tags[ProbeRuntime.Attribute.runID] == ProbeRuntime.runID else {
            record("trace-invalid-run", result: .fail)
            return nil
        }
        let source: ProbeSourceContext?
        if event.operationName == "urlsession.request", let url = URL(string: event.resource) {
            source = ProbeTraceOnlyURLSessionContract.sourceContext(from: url, expectedRunID: ProbeRuntime.runID)
        } else if event.operationName.hasPrefix("exp181.") {
            let phase = String(event.operationName.dropFirst("exp181.".count))
            source = ProbeSourceContext(logicalSceneID: ProbeTraceContract.source(for: phase), screen: "home", phase: phase)
        } else {
            source = nil
        }
        guard let source, let phase = source.phase, ProbeTraceContract.phases.contains(phase),
              let data = try? JSONEncoder().encode(event),
              let wire = ProbeTraceWireIdentity.decode(data) else {
            record("trace-invalid-payload", result: .fail)
            return nil
        }
        return ProbeSignal(
            kind: .rumTrace,
            evidenceSource: .traceMapper,
            sourceContext: source,
            rumContext: ProbeRUMContext(
                eventDateMilliseconds: wire.start / 1_000_000,
                sessionID: event.tags["_dd.session.id"],
                viewID: event.tags["_dd.view.id"],
                actionIDs: event.tags["_dd.action.id"].map { [$0] }
            ),
            eventID: wire.normalizedSpanID,
            name: phase,
            trace: ProbeTraceSignal(
                operationName: event.operationName,
                serviceName: event.serviceName,
                resourceName: event.resource,
                startTimeMilliseconds: wire.start / 1_000_000,
                durationNanoseconds: wire.duration,
                isError: event.isError,
                rumSessionID: event.tags["_dd.session.id"],
                rumViewID: event.tags["_dd.view.id"],
                rumActionIDs: event.tags["_dd.action.id"].map { [$0] },
                traceID: wire.fullTraceID,
                spanID: wire.normalizedSpanID,
                parentSpanID: wire.normalizedParentID,
                startTimeNanoseconds: wire.start,
                rumApplicationID: event.tags["_dd.application.id"]
            )
        )
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
        guard let ownerA = monitor.rumContextSnapshot(for: .scene(.init(rawValue: aID))),
              let ownerB = monitor.rumContextSnapshot(for: .scene(.init(rawValue: bID))) else {
            throw FixtureError.missing("both current SDK owners")
        }
        try require(ownerA.viewID != ownerB.viewID && ownerA.sessionID == ownerB.sessionID, "distinct current owners")
        record("trace-owner-a", context: ownerA)
        record("trace-owner-b", context: ownerB)
        let owner = monitor.rumContextHandoffOwner
        let otel = OTelTracerProvider().get(instrumentationName: "multi-scene-probe", instrumentationVersion: nil)
        var finishers: [String: () -> Void] = [:]
        func startPair(_ suffix: String) {
            let native = Tracer.shared().startRootSpan(operationName: "exp181.native-" + suffix)
            finishers["native-" + suffix] = { native.finish() }
            let span = otel.spanBuilder(spanName: "exp181.otel-" + suffix).setNoParent().startSpan()
            finishers["otel-" + suffix] = { span.end() }
        }
        func startRequest(_ suffix: String, source: String, nativeID: String) throws {
            let result = ProbeRuntime.startTraceOnlyURLSessionRequest(
                window: ProbeWindow(runID: ProbeRuntime.runID, label: source, opensPeer: false),
                sceneSessionID: nativeID,
                screen: "home",
                requestName: "url-" + suffix
            )
            guard case .accepted = result else { throw FixtureError.missing("request start " + suffix) }
        }
        record("trace-call-boundary")
        try RUMContextHandoff.withValue(owner: owner, rumContext: ownerA, sceneIdentifier: aID) {
            record("trace-start-a", context: ownerA)
            startPair("a")
            try startRequest("a", source: "scene-A", nativeID: aID)
        }
        try RUMContextHandoff.withValue(owner: owner, rumContext: ownerB, sceneIdentifier: bID) {
            record("trace-start-b", context: ownerB)
            startPair("b")
            try startRequest("b", source: "scene-B", nativeID: bID)
        }
        try require(RUMContextHandoff.current(for: owner) == nil, "source-less start inherited handoff")
        guard let fallback = monitor.rumContextSnapshot(for: .processRepresentative),
              fallback.viewID == ownerA.viewID || fallback.viewID == ownerB.viewID else {
            throw FixtureError.missing("independent process representative")
        }
        record("trace-fallback-empty-handoff")
        record("trace-start-fallback", context: fallback)
        startPair("fallback")
        try startRequest("fallback", source: "source-less", nativeID: "")
        record("trace-starts-enqueued")
        try await waitFor({
            let signals = ProbeRuntime.eventRecorder.snapshot()
            return ProbeTraceContract.urlPhases.allSatisfy { phase in
                signals.contains { $0.name == "trace-only-request-started-" + phase }
            }
        }, "three URL loaders")
        try require(!ProbeRuntime.eventRecorder.snapshot().contains { $0.kind == .rumTrace }, "premature span completion")
        try require(!ProbeRuntime.eventRecorder.snapshot().contains {
            $0.name?.hasPrefix("trace-only-request-completed-") == true
        }, "premature URL callback")
        record("trace-all-loaders-held")
        for phase in ProbeTraceContract.phases {
            let startOwner = phase.hasSuffix("-a") ? ownerA : phase.hasSuffix("-b") ? ownerB : fallback
            let peer = startOwner.viewID == ownerA.viewID ? ownerB : ownerA
            let peerID = peer.viewID == ownerA.viewID ? aID : bID
            try RUMContextHandoff.withValue(owner: owner, rumContext: peer, sceneIdentifier: peerID) {
                try require(RUMContextHandoff.current(for: owner)?.rumContext?.viewID == peer.viewID, "peer completion handoff")
                record("trace-finish-" + phase, context: peer)
                if phase.hasPrefix("url-") {
                    let result = ProbeRuntime.completeTraceOnlyURLSessionRequest(requestName: phase, releasingScene: peerID)
                    guard case .accepted = result else { throw FixtureError.missing("release " + phase) }
                } else {
                    guard let finish = finishers[phase] else { throw FixtureError.missing("finisher " + phase) }
                    finish()
                    finish()
                }
            }
            try await waitFor({
                ProbeRuntime.eventRecorder.snapshot().contains { $0.kind == .rumTrace && $0.name == phase }
            }, "completed span " + phase)
            if phase.hasPrefix("url-") {
                try await waitFor({
                    ProbeRuntime.eventRecorder.snapshot().contains { $0.name == "trace-only-request-completed-" + phase }
                }, "URL callback " + phase)
            }
        }
        let traces = ProbeRuntime.eventRecorder.snapshot().filter { $0.kind == .rumTrace }
        try require(traces.map(\.name) == ProbeTraceContract.phases.map(Optional.some), "exact nine-span completion order")
        for trace in traces {
            let phase = trace.name ?? ""
            let expected = phase.hasSuffix("-a") ? ownerA : phase.hasSuffix("-b") ? ownerB : fallback
            try require(
                trace.rumContext?.viewID == expected.viewID && trace.rumContext?.sessionID == expected.sessionID,
                "captured completion owner " + phase
            )
        }
        record("trace-local-owners-verified")
    }
    #endif
}

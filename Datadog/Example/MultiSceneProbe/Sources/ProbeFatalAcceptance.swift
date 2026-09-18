/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
@_spi(Internal)
import DatadogCore
#if DEBUG
@testable import DatadogCrashReporting
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

internal enum ProbeFatalAcceptance {
    #if DEBUG
    @MainActor private static var running = false
    private enum FixtureError: Error { case missing(String) }

    private static var recorder: ProbeEventRecorder { ProbeRuntime.eventRecorder }
    private static var scenarioID: String { ProbeRuntime.resolution.scenario?.identifier ?? "" }

    static func configure() {
        if scenarioID == ProbeFatalContract.prepare {
            CrashReporting.enable()
        }
    }

    private static func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw FixtureError.missing(label) }
    }

    private static func record(
        _ name: String,
        owner: RUMCoreContext? = nil,
        source: ProbeSourceContext? = nil,
        observed: ProbeFatalObservation? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        recorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .internalHook,
            sourceContext: source,
            rumContext: owner.map {
                .init(sessionID: $0.sessionID, viewID: $0.viewID, viewName: $0.viewName)
            },
            name: name,
            fatal: observed ?? .init(processID: ProcessInfo.processInfo.processIdentifier),
            result: result,
            reason: reason
        ))
    }

    private static func context() async -> DatadogContext {
        await withCheckedContinuation { continuation in
            CoreRegistry.default.scope(for: RUMFeature.self).context {
                continuation.resume(returning: $0)
            }
        }
    }

    @MainActor
    private static func waitFor(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing(label)
    }

    private static func feature() throws -> CrashReportingFeature {
        guard let feature = CoreRegistry.default.feature(named: CrashReportingFeature.name, type: CrashReportingFeature.self) else {
            throw FixtureError.missing("real crash reporting feature")
        }
        try require(feature.plugin is KSCrashPlugin, "real KSCrash plugin")
        return feature
    }

    private static func provider(_ feature: CrashReportingFeature) throws -> CrashContextCoreProvider {
        guard let provider = feature.crashContextProvider as? CrashContextCoreProvider else {
            throw FixtureError.missing("real crash context provider")
        }
        return provider
    }

    @MainActor
    static func prepare() -> ProbeStepExecutionResult {
        guard !running else {
            return .rejected(reason: "fatal preparation already started")
        }
        running = true
        Task { @MainActor in
            do {
                let owner = try await prepareCrash()
                record(ProbeFatalContract.prepared)
                try await waitFor("preparation terminal verdict") { recorder.recordedTerminalResult() != nil }
                try require(recorder.recordedTerminalResult()?.state == .pass, "preparation PASS")
                DispatchQueue.global(qos: .utility).async {
                    guard let monitor = RUMMonitor.shared() as? Monitor,
                          RUMContextHandoff.current(for: monitor.rumContextHandoffOwner) == nil else {
                        record("fatal-crash-boundary", result: .fail, reason: "unexpected source handoff")
                        return
                    }
                    record("fatal-crash-boundary", owner: owner)
                    fflush(stdout)
                    abort()
                }
            } catch {
                record(ProbeFatalContract.prepared, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    @MainActor
    private static func prepareCrash() async throws -> RUMCoreContext {
        record("fatal-process")
        guard let monitor = RUMMonitor.shared() as? Monitor else {
            throw FixtureError.missing("real RUM monitor")
        }
        let feature = try feature()
        let provider = try provider(feature)
        var owners: [String: RUMCoreContext] = [:]
        var nativeIDs: [String: String] = [:]
        for scene in ["scene-A", "scene-B"] {
            guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: scene),
                  let window = ProbeRuntime.sceneRegistry.window(for: handle),
                  let nativeID = window.windowScene?.session.persistentIdentifier,
                  let owner = monitor.rumContextSnapshot(for: .scene(.init(rawValue: nativeID))),
                  let viewID = owner.viewID else { throw FixtureError.missing("native owner " + scene) }
            try require(recorder.snapshot().contains {
                $0.kind == .rumViewSnapshot && $0.evidenceSource == .rumMapper
                    && $0.rumContext?.viewID == viewID && $0.rumContext?.viewActive == true
                    && $0.semanticContext?.logicalSceneID == scene
            }, "independent active Home mapper")
            owners[scene] = owner
            nativeIDs[scene] = nativeID
            record(
                "fatal-owner-" + (scene == "scene-A" ? "a" : "b"),
                owner: owner,
                source: .init(logicalSceneID: scene, nativeSceneID: nativeID, screen: "home")
            )
        }
        guard let capturedA = owners["scene-A"], let ownerB = owners["scene-B"],
              let nativeA = nativeIDs["scene-A"], let nativeB = nativeIDs["scene-B"] else {
            throw FixtureError.missing("two distinct owners")
        }
        try require(nativeA != nativeB && capturedA.viewID != ownerB.viewID, "distinct native scenes and views")
        try require(capturedA.sessionID == ownerB.sessionID, "shared current session")
        try require(await context().additionalContext(ofType: LaunchReport.self)?.didCrash == false, "clean crash store")
        try await checkExportAndProvider("before", owner: ownerB, provider: provider)

        monitor.addAttribute(forKey: ProbeRuntime.Attribute.phase, value: "fatal-original")
        record("fatal-mutation-dispatched", owner: capturedA)
        monitor.addViewAttributes(["exp184_peer_mutation": "A"], explicitTarget: .scene(.init(rawValue: nativeA)))
        monitor.addTiming(name: "exp184_peer_mutation_visible", explicitTarget: .scene(.init(rawValue: nativeA)))
        try await waitFor("peer mapper update") {
            recorder.snapshot().contains {
                $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == capturedA.viewID
                    && $0.fatal?.peerMutation == "A" && $0.fatal?.mutationTiming != nil
            }
        }
        try await checkExportAndProvider("after", owner: ownerB, provider: provider)
        try require(
            monitor.rumContextSnapshot(for: .scene(.init(rawValue: nativeA))) == capturedA,
            "retained A value"
        )
        record("fatal-capture-unchanged", owner: capturedA)
        try await waitFor("original run and phase in crash provider") {
            provider.currentCrashContext?.lastRUMAttributes?.contextInfo[ProbeRuntime.Attribute.runID] as? String
                == ProbeRuntime.runID
                && provider.currentCrashContext?.lastRUMAttributes?.contextInfo[ProbeRuntime.Attribute.phase] as? String
                == "fatal-original"
        }
        // Drain stored telemetry before the intentional process boundary, off the main actor.
        await Task.detached { Datadog.flush() }.value
        provider.flush()
        feature.flush()
        try require(provider.currentCrashContext?.lastRUMViewEvent?.view.id == ownerB.viewID, "injected B")
        record(
            "fatal-injection-drained",
            owner: ownerB,
            observed: provider.currentCrashContext?.lastRUMViewEvent.map(viewObservation)
        )
        return ownerB
    }

    @MainActor
    private static func checkExportAndProvider(
        _ suffix: String, owner: RUMCoreContext, provider: CrashContextCoreProvider
    ) async throws {
        let exported = await context().additionalContext(ofType: RUMCoreContext.self)
        try require(exported == owner, "Core export " + suffix)
        record("fatal-export-" + suffix, owner: exported)
        try await waitFor("crash provider " + suffix) {
            let view = provider.currentCrashContext?.lastRUMViewEvent
            return view?.view.id == owner.viewID && view?.session.id == owner.sessionID
        }
        let view = provider.currentCrashContext?.lastRUMViewEvent
        recorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .internalHook,
            rumContext: .init(sessionID: view?.session.id, viewID: view?.view.id, viewName: view?.view.name),
            name: "fatal-provider-" + suffix,
            fatal: .init(processID: ProcessInfo.processInfo.processIdentifier),
            result: .pass
        ))
    }

    @MainActor
    static func recover() async {
        guard !running else {
            return
        }
        running = true
        do {
            try await recoverReport()
        } catch {
            record("fatal-recovery-failed", result: .fail, reason: String(describing: error))
        }
        guard let scenario = ProbeRuntime.resolution.scenario else {
            return
        }
        recorder.recordTerminalResult(ProbeSemanticOracle.evaluate(scenario: scenario, signals: recorder.snapshot()))
    }

    @MainActor
    private static func recoverReport() async throws {
        record("fatal-process")
        try require(ProbeFatalContract.isRecovery(scenarioID), "declared recovery phase")
        try require(await context().additionalContext(ofType: LaunchReport.self) == nil, "reporter not yet enabled")
        guard let monitor = RUMMonitor.shared() as? Monitor else { throw FixtureError.missing("RUM monitor") }
        monitor.startView(key: "fatal-recovery", name: "FatalRecovery", attributes: [:])
        try await waitFor("current recovery mapper") {
            recorder.snapshot().contains {
                $0.kind == .rumViewSnapshot && $0.rumContext?.viewName == "FatalRecovery"
                    && $0.rumContext?.viewActive == true
            }
        }
        let current = await context().additionalContext(ofType: RUMCoreContext.self)
        try require(current?.viewName == "FatalRecovery" && current?.viewID != nil, "current recovery export")
        record("fatal-recovery-current", owner: current)
        record("fatal-reporter-enable")
        CrashReporting.enable()
        var launch: LaunchReport?
        for _ in 0..<500 {
            launch = await context().additionalContext(ofType: LaunchReport.self)
            if launch != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let expectedCrash = scenarioID == ProbeFatalContract.recover
        try require(launch?.didCrash == expectedCrash, "actual launch report acknowledgement")
        record("fatal-launch-report", observed: .init(
            processID: ProcessInfo.processInfo.processIdentifier, launchDidCrash: launch?.didCrash
        ))
        let feature = try feature()
        try provider(feature).flush()
        feature.flush()
        if expectedCrash {
            try await waitFor("actual recovered fatal mapper") {
                recorder.snapshot().contains { $0.kind == .rumError && $0.error?.isCrash == true }
            }
            try await waitFor("recovered view count update") {
                recorder.snapshot().contains { $0.kind == .rumViewSnapshot && $0.fatal?.viewCrashCount == 1 }
            }
        }
        let errors = recorder.snapshot().filter { $0.kind == .rumError }
        try require(errors.count == (expectedCrash ? 1 : 0), "exact fatal mapper count")
        if let error = errors.first {
            try require(error.rumContext?.sessionID != current?.sessionID
                        && error.rumContext?.viewID != current?.viewID, "old owner differs from current")
        }
        await Task.detached { Datadog.flush() }.value
        record("fatal-recovery-complete", owner: current)
    }

    static func viewObservation(_ event: RUMViewEvent) -> ProbeFatalObservation {
        .init(
            processID: ProcessInfo.processInfo.processIdentifier,
            originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID] as? String,
            documentVersion: event.dd.documentVersion,
            viewErrorCount: event.view.error.count,
            viewCrashCount: event.view.crash?.count ?? 0,
            peerMutation: event.context?.contextInfo["exp184_peer_mutation"] as? String,
            mutationTiming: event.view.customTimings?.customTimingsInfo["exp184_peer_mutation_visible"]
        )
    }

    static func recordPayload(_ event: RUMErrorEvent) {
        let valid = event.error.isCrash == true && event.error.source == .source
            && event.source == .ios && event.action == nil && event.container == nil
            && event.error.meta?.exceptionType == "SIGABRT"
        recorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .rumMapper,
            rumContext: .init(sessionID: event.session.id, viewID: event.view.id, viewName: event.view.name),
            eventID: event.error.id,
            name: "fatal-error-payload",
            fatal: .init(
                processID: ProcessInfo.processInfo.processIdentifier,
                originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID] as? String,
                incidentIdentifier: event.error.meta?.incidentIdentifier,
                exceptionType: event.error.meta?.exceptionType,
                crashedProcess: event.error.meta?.process,
                nativeSource: event.source?.rawValue,
                hasAction: event.action != nil,
                hasContainer: event.container != nil
            ),
            result: valid ? .pass : .fail
        ))
    }
    #else
    static func configure() {}
    static func prepare() -> ProbeStepExecutionResult { .rejected(reason: "fatal acceptance requires Debug") }
    @MainActor
    static func recover() async {}
    #endif
}

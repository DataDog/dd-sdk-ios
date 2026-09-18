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
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

internal enum ProbeVitalsAcceptance {
    #if DEBUG
    @MainActor private static var started: Set<String> = []
    @MainActor private static var ownerA: RUMCoreContext?
    private enum FixtureError: Error { case missing(String) }
    private static var recorder: ProbeEventRecorder { ProbeRuntime.eventRecorder }

    private static func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw FixtureError.missing(label) }
    }

    private static func record(
        _ name: String,
        owner: RUMCoreContext? = nil,
        source: ProbeSourceContext? = nil,
        observed: ProbeVitalsObservation? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        recorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .internalHook,
            sourceContext: source,
            rumContext: owner.map { .init(sessionID: $0.sessionID, viewID: $0.viewID) },
            name: name,
            vitals: observed,
            result: result,
            reason: reason
        ))
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

    private static func latest(_ owner: RUMCoreContext) -> ProbeSignal? {
        recorder.snapshot().last {
            $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == owner.viewID
                && $0.rumContext?.sessionID == owner.sessionID
        }
    }

    @MainActor
    static func start(scene label: String) -> ProbeStepExecutionResult {
        guard ["scene-A", "scene-B"].contains(label), started.insert(label).inserted else {
            return .rejected(reason: "vitals phase missing or already started")
        }
        let suffix = label == "scene-A" ? "a" : "b"
        Task.detached { @MainActor in
            do {
                try await run(label: label, suffix: suffix)
                record("vitals-" + suffix + "-complete")
            } catch {
                record("vitals-" + suffix + "-complete", result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    @MainActor
    private static func configuration(_ feature: RUMFeature, monitor: Monitor) throws {
        let config = feature.configuration
        let dependencies = monitor.applicationScope.dependencies
        guard let readers = dependencies.vitalsReaders else { throw FixtureError.missing("actual shared readers") }
        let installed = [
            "cpu": readers.cpu is VitalCPUReader,
            "memory": readers.memory is VitalMemoryReader,
            "refreshRate": readers.refreshRate is VitalRefreshRateReader,
            "renderLoop": dependencies.renderLoopObserver != nil,
            "slowFrames": config.trackSlowFrames && dependencies.viewHitchesReaderFactory != nil,
            "longTasksDisabled": config.longTaskThreshold == nil && feature.instrumentation.longTasks == nil,
            "appHangsDisabled": config.appHangThreshold == nil && feature.instrumentation.appHangs == nil,
            "memoryWarningsDisabled": !config.trackMemoryWarnings && feature.instrumentation.memoryWarningMonitor == nil,
            "timeseriesDefaultDisabled": config.timeseries == nil && feature.timeseriesCollector == nil,
        ]
        try require(readers.frequency == 0.1 && installed.values.allSatisfy { $0 }, "actual vitals configuration")
        record("vitals-configuration", observed: .init(configuration: installed, samplingInterval: readers.frequency))
    }

    @MainActor
    private static func scene(_ label: String, suffix: String, monitor: Monitor) throws -> (UIWindowScene, RUMCoreContext) {
        guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: label),
              let scene = ProbeRuntime.sceneRegistry.window(for: handle)?.windowScene,
              let owner = monitor.rumContextSnapshot(for: .scene(.init(rawValue: scene.session.persistentIdentifier))),
              let viewID = owner.viewID else { throw FixtureError.missing("native owner " + label) }
        let nativeID = scene.session.persistentIdentifier
        try require(recorder.snapshot().contains {
            $0.kind == .sceneReady && $0.semanticContext?.logicalSceneID == label
                && $0.semanticContext?.nativeSceneID == nativeID && $0.scenePhase == "ready"
        }, "independent native readiness")
        try require(recorder.snapshot().contains {
            $0.kind == .rumViewSnapshot && $0.evidenceSource == .rumMapper
                && $0.rumContext?.viewID == viewID && $0.rumContext?.viewActive == true
                && $0.semanticContext?.logicalSceneID == label
        }, "independent active Home mapper")
        record(
            "vitals-" + suffix + "-owner",
            owner: owner,
            source: .init(logicalSceneID: label, nativeSceneID: nativeID, screen: "home")
        )
        return (scene, owner)
    }

    @MainActor
    private static func run(label: String, suffix: String) async throws {
        guard #available(iOS 27.0, *),
              let feature = CoreRegistry.default.feature(named: RUMFeature.name, type: RUMFeature.self),
              let monitor = RUMMonitor.shared() as? Monitor else {
            throw FixtureError.missing("actual RUM feature")
        }
        if label == "scene-A" { try configuration(feature, monitor: monitor) }
        let (scene, owner) = try self.scene(label, suffix: suffix, monitor: monitor)
        if label == "scene-A" {
            ownerA = owner
        } else {
            guard let ownerA,
                  let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: "scene-A"),
                  let originalScene = ProbeRuntime.sceneRegistry.window(for: handle)?.windowScene else {
                throw FixtureError.missing("original A owner")
            }
            try require(originalScene !== scene && ownerA.viewID != owner.viewID
                        && ownerA.sessionID == owner.sessionID, "distinct scenes in one session")
            try await waitFor("original A retired before B sampling") {
                originalScene.activationState == .background && latest(ownerA)?.rumContext?.viewActive == false
            }
            record("vitals-a-retired", owner: ownerA)
        }
        record("vitals-" + suffix + "-sampling-began", owner: owner)
        let boundary = recorder.snapshot().last?.sequence ?? 0
        var sampled = false
        for _ in 0..<100 {
            monitor.addTiming(name: "exp186_" + suffix, view: .current(in: scene))
            try await Task.sleep(nanoseconds: 100_000_000)
            if let view = latest(owner), view.sequence > boundary, view.rumContext?.viewActive == true,
               let vitals = view.vitals, hasSamples(vitals) {
                sampled = true
                break
            }
        }
        try require(sampled, "actual CPU, memory and render-loop samples")
        record("vitals-" + suffix + "-samples-acknowledged", owner: owner)
        if label == "scene-B" { try await finish(ownerB: owner, monitor: monitor) }
    }

    private static func hasSamples(_ value: ProbeVitalsObservation) -> Bool {
        guard let cpu = value.cpuTicks, let rate = value.cpuRate,
              let memory = value.memoryAverage, let maximum = value.memoryMax,
              let refresh = value.refreshRateAverage, let minimum = value.refreshRateMin,
              let time = value.timeSpentNanoseconds else { return false }
        return [cpu, rate, memory, maximum, refresh, minimum].allSatisfy { $0.isFinite && $0 > 0 }
            && maximum >= memory && minimum <= refresh && time > 1_000_000_000
    }

    @MainActor
    private static func finish(ownerB: RUMCoreContext, monitor: Monitor) async throws {
        guard let ownerA else { throw FixtureError.missing("A owner at final boundary") }
        record("vitals-stop-boundary", owner: ownerB)
        monitor.stopSession()
        try await waitFor("both final inactive views") {
            latest(ownerA)?.rumContext?.viewActive == false && latest(ownerB)?.rumContext?.viewActive == false
        }
        for (suffix, owner) in [("a", ownerA), ("b", ownerB)] {
            guard let view = latest(owner), let vitals = view.vitals else {
                throw FixtureError.missing("final actual vitals")
            }
            try require(hasSamples(vitals), "final metric fields")
            record("vitals-final-" + suffix, owner: owner, observed: vitals)
        }
        let signals = recorder.snapshot()
        try require(!signals.contains {
            [.rumAction, .rumResource, .rumError, .rumLongTask, .rumLog, .rumTrace, .rumOperation].contains($0.kind)
        }, "unexpected telemetry")
        let views = signals.filter { $0.kind == .rumViewSnapshot }
        let ids = Set(views.compactMap { $0.rumContext?.viewID })
        try require(
            ids.count == 3 && Set(views.compactMap { $0.rumContext?.sessionID }).count == 1,
            "complete three-view inventory"
        )
        for id in ids {
            guard let view = views.last(where: { $0.rumContext?.viewID == id }) else {
                throw FixtureError.missing("final view snapshot")
            }
            try require(view.rumContext?.viewActive == false
                        && view.vitals?.counters == ProbeVitalsContract.zeroCounters, "final inactive zero-count view")
        }
        record("vitals-inventory-verified")
    }

    static func viewObservation(_ event: RUMViewEvent) -> ProbeVitalsObservation {
        .init(
            cpuTicks: event.view.cpuTicksCount,
            cpuRate: event.view.cpuTicksPerSecond,
            memoryAverage: event.view.memoryAverage,
            memoryMax: event.view.memoryMax,
            refreshRateAverage: event.view.refreshRateAverage,
            refreshRateMin: event.view.refreshRateMin,
            timeSpentNanoseconds: event.view.timeSpent,
            slowFrames: event.view.slowFrames?.map { .init(start: $0.start, duration: $0.duration) },
            slowFramesRate: event.view.slowFramesRate,
            nativeSource: event.source?.rawValue,
            originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID]?.dd.decode(),
            counters: [
                "actions": event.view.action.count, "resources": event.view.resource.count,
                "errors": event.view.error.count, "longTasks": event.view.longTask?.count ?? 0,
                "crashes": event.view.crash?.count ?? 0,
            ]
        )
    }
    #else
    @MainActor
    static func start(scene: String) -> ProbeStepExecutionResult {
        .rejected(reason: "vitals acceptance requires the Debug fixture")
    }
    #endif
}

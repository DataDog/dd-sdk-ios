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

internal enum ProbeProcessAcceptance {
    #if DEBUG
    @MainActor private static var running = false
    private enum FixtureError: Error { case missing(String) }
    private static var recorder: ProbeEventRecorder { ProbeRuntime.eventRecorder }

    private static func require(_ condition: Bool, _ label: String) throws {
        if !condition { throw FixtureError.missing(label) }
    }

    private static func record(
        _ name: String,
        owner: RUMCoreContext? = nil,
        source: ProbeSourceContext? = nil,
        observed: ProbeProcessObservation? = nil,
        result: ProbeSemanticResultState = .pass,
        reason: String? = nil
    ) {
        recorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .internalHook,
            sourceContext: source,
            rumContext: owner.map {
                .init(sessionID: $0.sessionID, viewID: $0.viewID, actionIDs: $0.userActionID.map { [$0] })
            },
            name: name,
            processSignal: observed,
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

    private static func context() async -> DatadogContext {
        await withCheckedContinuation { continuation in
            CoreRegistry.default.scope(for: RUMFeature.self).context { continuation.resume(returning: $0) }
        }
    }

    @MainActor
    static func start() -> ProbeStepExecutionResult {
        guard !running else {
            return .rejected(reason: "process signal batch already started")
        }
        running = true
        Task.detached { @MainActor in
            do {
                try await run()
                record(ProbeProcessContract.completed)
            } catch {
                record(ProbeProcessContract.completed, result: .fail, reason: String(describing: error))
            }
        }
        return .accepted
    }

    @MainActor
    private static func scene(_ label: String, monitor: Monitor) throws -> (UIWindowScene, RUMCoreContext) {
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
            "process-owner-" + (label == "scene-A" ? "a" : "b"),
            owner: owner,
            source: .init(logicalSceneID: label, nativeSceneID: nativeID, screen: "home")
        )
        return (scene, owner)
    }

    @MainActor
    private static func run() async throws {
        guard #available(iOS 27.0, *),
              let feature = CoreRegistry.default.feature(named: RUMFeature.name, type: RUMFeature.self),
              let monitor = RUMMonitor.shared() as? Monitor,
              let observer = feature.instrumentation.longTasks,
              let begin = observer.observer_begin, let end = observer.observer_end else {
            throw FixtureError.missing("real process instrumentation")
        }
        let config = feature.configuration
        let observed = ProbeProcessObservation(
            longTaskThreshold: config.longTaskThreshold,
            appHangThreshold: config.appHangThreshold,
            hasLongTaskObserver: CFRunLoopContainsObserver(CFRunLoopGetMain(), begin, .commonModes)
                && CFRunLoopContainsObserver(CFRunLoopGetMain(), end, .commonModes),
            hasAppHangMonitor: feature.instrumentation.appHangs != nil,
            hasMemoryWarningMonitor: config.trackMemoryWarnings && feature.instrumentation.memoryWarningMonitor != nil
        )
        try require(observed.longTaskThreshold == 0.5 && observed.appHangThreshold == 0.5
                    && observed.hasLongTaskObserver == true && observed.hasAppHangMonitor == true
                    && observed.hasMemoryWarningMonitor == true, "actual configuration")
        record("process-configuration", observed: observed)
        let (sceneA, initialOwnerA) = try scene("scene-A", monitor: monitor)
        let (sceneB, ownerB) = try scene("scene-B", monitor: monitor)
        try require(sceneA !== sceneB && initialOwnerA.viewID != ownerB.viewID
                    && initialOwnerA.sessionID == ownerB.sessionID, "two distinct scene owners")
        try await round("b", owner: ownerB, monitor: monitor)
        let ownerA = try await reactivate(sceneA, initialOwner: initialOwnerA, monitor: monitor)

        record("process-selection-boundary")
        monitor.addAction(type: .custom, name: ProbeProcessContract.selection, view: .current(in: sceneA), attributes: [:])
        try await waitFor("selection Action") {
            recorder.snapshot().contains { $0.kind == .rumAction && $0.action?.target == ProbeProcessContract.selection }
        }
        let selected = recorder.snapshot().filter { $0.kind == .rumAction }
        try require(selected.count == 1 && selected.first?.rumContext?.viewID == ownerA.viewID
                    && selected.first?.rumContext?.sessionID == ownerA.sessionID, "selection owner")
        record("process-selection-acknowledged", owner: ownerA)
        try await round("a", owner: ownerA, monitor: monitor)
        let signals = recorder.snapshot()
        try require(signals.filter { $0.kind == .rumLongTask }.count == 2
                    && signals.filter { $0.kind == .rumError }.count == 4
                    && signals.filter { $0.kind == .rumAction }.count == 1, "complete process inventory")
        try require(
            !signals.contains { [.rumResource, .rumLog, .rumTrace, .rumOperation].contains($0.kind) },
            "unexpected telemetry"
        )
        let views = signals.filter { $0.kind == .rumViewSnapshot }
        let viewIDs = Set(views.compactMap { $0.rumContext?.viewID })
        try require(viewIDs.count == 4, "complete view inventory")
        for id in viewIDs {
            guard let view = views.last(where: { $0.rumContext?.viewID == id }) else {
                throw FixtureError.missing("final view")
            }
            let count: Int64 = id == ownerA.viewID || id == ownerB.viewID ? 1 : 0
            try require(view.processSignal?.viewLongTaskCount == count
                        && view.processSignal?.viewErrorCount == 2 * count
                        && view.processSignal?.viewActionCount == (id == ownerA.viewID ? 1 : 0)
                        && view.processSignal?.viewResourceCount == 0
                        && view.processSignal?.viewCrashCount == 0, "final owner counts")
        }
        record("process-inventory-verified")
    }

    @MainActor
    private static func reactivate(
        _ scene: UIWindowScene,
        initialOwner: RUMCoreContext,
        monitor: Monitor
    ) async throws -> RUMCoreContext {
        try await waitFor("initial A retired") {
            scene.activationState == .background && recorder.snapshot().last {
                $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == initialOwner.viewID
            }?.rumContext?.viewActive == false
        }
        record("process-a-retired", owner: initialOwner)
        guard let application = UIApplication.dd.managedShared else {
            throw FixtureError.missing("application for actual scene activation")
        }
        let nativeID = scene.session.persistentIdentifier
        let source = ProbeSourceContext(logicalSceneID: "scene-A", nativeSceneID: nativeID, screen: "home")
        record("process-a-activation-requested", source: source)
        let boundary = recorder.snapshot().last?.sequence ?? 0
        application.requestSceneSessionActivation(scene.session, userActivity: nil, options: nil) { _ in
            record(ProbeProcessContract.completed, result: .fail, reason: "actual A activation failed")
        }
        try await waitFor("fresh A activation and owner") {
            guard scene.activationState == .foregroundActive,
                  let owner = monitor.rumContextSnapshot(for: .scene(.init(rawValue: nativeID))),
                  let viewID = owner.viewID, viewID != initialOwner.viewID,
                  owner.sessionID == initialOwner.sessionID else { return false }
            let fresh = recorder.snapshot().filter { $0.sequence > boundary }
            return fresh.contains {
                $0.kind == .sceneLifecycle && $0.semanticContext?.nativeSceneID == nativeID
                    && $0.semanticContext?.logicalSceneID == "scene-A" && $0.activationState == "foreground-active"
            } && fresh.contains {
                $0.kind == .rumViewSnapshot && $0.evidenceSource == .rumMapper
                    && $0.rumContext?.viewID == viewID && $0.rumContext?.viewActive == true
                    && $0.semanticContext?.logicalSceneID == "scene-A"
            }
        }
        guard let restored = monitor.rumContextSnapshot(for: .scene(.init(rawValue: nativeID))) else {
            throw FixtureError.missing("restored A owner")
        }
        record("process-a-activation-acknowledged", owner: restored, source: source)
        return restored
    }

    @MainActor
    private static func round(_ suffix: String, owner: RUMCoreContext, monitor: Monitor) async throws {
        let exported = await context()
        let representative = exported.additionalContext(ofType: RUMCoreContext.self)
        try require(
            representative?.viewID == owner.viewID && representative?.sessionID == owner.sessionID
                && representative?.userActionID == nil
                && monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == owner.viewID,
            "representative before stimulus"
        )
        try require(RUMContextHandoff.current(for: monitor.rumContextHandoffOwner) == nil, "empty process handoff")
        record(
            "process-" + suffix + "-representative",
            owner: representative,
            observed: .init(serverTimeOffsetMilliseconds: exported.serverTimeOffset * 1_000)
        )
        let before = recorder.snapshot().last?.sequence ?? 0
        record("process-" + suffix + "-memory-boundary")
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        try await waitFor("memory warning mapper") {
            recorder.snapshot().contains { $0.sequence > before && $0.kind == .rumError && $0.error?.type == "MemoryWarning" }
        }
        let memory = recorder.snapshot().filter { $0.sequence > before && $0.kind == .rumError }
        try require(memory.count == 1 && memory.first?.rumContext?.viewID == owner.viewID, "memory owner/count")
        record("process-" + suffix + "-memory-acknowledged")
        blockMainThread(suffix)
        try await waitFor("long task, hang and count updates") {
            let signals = recorder.snapshot()
            let events = signals.filter { $0.sequence > before }
            let view = signals.last { $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == owner.viewID }
            return events.contains { $0.kind == .rumLongTask }
                && events.contains { $0.kind == .rumError && $0.error?.type == "AppHang" }
                && view?.processSignal?.viewLongTaskCount == 1 && view?.processSignal?.viewErrorCount == 2
        }
        let events = recorder.snapshot().filter {
            $0.sequence > before && [.rumError, .rumLongTask].contains($0.kind)
        }
        try require(events.count == 3 && events.filter { $0.kind == .rumLongTask }.count == 1
                    && Set(events.compactMap(\.eventID)).count == 3, "one event per actual producer")
        for event in events {
            try require(
                event.rumContext?.viewID == owner.viewID && event.rumContext?.sessionID == owner.sessionID
                    && event.processSignal?.nativeSource == "ios" && event.processSignal?.hasAction == false
                    && event.processSignal?.hasContainer == false && event.processSignal?.originalRunID == ProbeRuntime.runID,
                "exact process event owner and payload"
            )
            if event.kind == .rumLongTask || event.error?.type == "AppHang" {
                guard let duration = event.processSignal?.durationNanoseconds else {
                    throw FixtureError.missing("measured duration")
                }
                try require(duration >= 500_000_000 && duration < 5_000_000_000, "bounded real duration")
            }
            if event.kind == .rumError {
                try require(event.error?.isCrash == false, "nonfatal process error")
            }
        }
        try require(
            monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == owner.viewID,
            "process signals changed representative"
        )
        record("process-" + suffix + "-signals-acknowledged", owner: owner)
    }

    @MainActor
    private static func blockMainThread(_ suffix: String) {
        record("process-" + suffix + "-block-began")
        Thread.sleep(forTimeInterval: 1.5)
        record("process-" + suffix + "-block-ended")
    }

    static func viewObservation(_ event: RUMViewEvent) -> ProbeProcessObservation {
        .init(
            nativeSource: event.source?.rawValue,
            originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID]?.dd.decode(),
            viewLongTaskCount: event.view.longTask?.count ?? 0,
            viewErrorCount: event.view.error.count,
            viewActionCount: event.view.action.count,
            viewResourceCount: event.view.resource.count,
            viewCrashCount: event.view.crash?.count ?? 0
        )
    }

    static func errorObservation(_ event: RUMErrorEvent) -> ProbeProcessObservation {
        .init(
            durationNanoseconds: event.freeze?.duration,
            nativeSource: event.source?.rawValue,
            originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID]?.dd.decode(),
            hasAction: event.action != nil,
            hasContainer: event.container != nil
        )
    }

    static func recordLongTask(_ event: RUMLongTaskEvent) {
        recorder.record(ProbeSignal(
            kind: .rumLongTask,
            evidenceSource: .rumMapper,
            rumContext: .init(
                eventDateMilliseconds: event.date,
                sessionID: event.session.id,
                viewID: event.view.id,
                viewName: event.view.name,
                viewURL: event.view.url
            ),
            eventID: event.longTask.id,
            name: "LongTask",
            processSignal: .init(
                durationNanoseconds: event.longTask.duration,
                nativeSource: event.source?.rawValue,
                originalRunID: event.context?.contextInfo[ProbeRuntime.Attribute.runID]?.dd.decode(),
                hasAction: event.action != nil,
                hasContainer: event.container != nil
            )
        ))
    }
    #else
    @MainActor
    static func start() -> ProbeStepExecutionResult {
        .rejected(reason: "process acceptance requires the Debug fixture")
    }
    #endif
}

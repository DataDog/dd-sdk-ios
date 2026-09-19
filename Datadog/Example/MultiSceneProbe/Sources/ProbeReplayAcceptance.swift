/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import DatadogCore
import DatadogSessionReplay
#if DEBUG
@_spi(Experimental)
@testable import DatadogRUM
@_spi(Internal)
import DatadogInternal
#endif

internal enum ProbeReplayAcceptance {
    #if DEBUG
    @MainActor private static var nextPhase = 0
    @MainActor private static var running = false

    static func configure() {
        SessionReplay.enable(with: .init(replaySampleRate: 100))
    }

    @MainActor
    static func capture(scene: String, phase: String) -> ProbeStepExecutionResult {
        guard !running, nextPhase < ProbeReplayContract.phases.count,
              ProbeReplayContract.phases[nextPhase] == phase,
              ProbeReplayContract.scenes[nextPhase] == scene else {
            return .rejected(reason: "Replay checkpoint is repeated or out of order")
        }
        running = true
        Task { @MainActor in
            defer { running = false }
            do {
                try await sample(scene: scene, phase: phase)
                nextPhase += 1
            } catch {
                ProbeRuntime.eventRecorder.record(ProbeSignal(
                    kind: .assertion,
                    semanticContext: .init(logicalSceneID: scene),
                    name: phase,
                    result: .fail,
                    reason: String(describing: error)
                ))
            }
        }
        return .accepted
    }

    private enum FixtureError: Error { case missing(String) }

    private static func context() async -> (Bool, [String: Int64]) {
        await withCheckedContinuation { continuation in
            CoreRegistry.default.scope(for: RUMFeature.self).context { context in
                continuation.resume(returning: (context.hasReplay == true, context.recordsCountByViewID))
            }
        }
    }

    @MainActor
    private static func topology() throws -> [ProbeReplaySceneObservation] {
        try ["scene-A", "scene-B"].compactMap { label in
            guard let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: label),
                  let window = ProbeRuntime.sceneRegistry.window(for: handle),
                  let scene = window.windowScene else { return nil }
            guard scene.session.persistentIdentifier == handle.nativeSceneID,
                  UIApplication.shared.connectedScenes.contains(scene) else {
                throw FixtureError.missing("connected native scene " + label)
            }
            let live = ProbeScenePresentation.capture(window: window)
            guard let geometry = live.geometry, geometry.width > 0, geometry.height > 0 else {
                throw FixtureError.missing("native geometry " + label)
            }
            return ProbeReplaySceneObservation(
                logicalSceneID: label,
                nativeSceneID: handle.nativeSceneID,
                activationState: live.activationState.rawValue,
                geometry: geometry
            )
        }
    }

    @MainActor
    private static func record(
        _ name: String,
        scene: String,
        native: String,
        owner: RUMCoreContext,
        context: (Bool, [String: Int64]),
        topology: [ProbeReplaySceneObservation]
    ) {
        ProbeRuntime.eventRecorder.record(ProbeSignal(
            kind: .assertion,
            evidenceSource: .internalHook,
            semanticContext: .init(
                logicalSceneID: scene, nativeSceneID: native,
                screen: ProbeReplayContract.screens[nextPhase], occurrence: 1
            ),
            rumContext: .init(sessionID: owner.sessionID, sessionHasReplay: context.0,
                              viewID: owner.viewID, viewName: owner.viewName),
            name: name,
            replay: .init(hasReplay: context.0, recordsByViewID: context.1, scenes: topology),
            result: .pass
        ))
    }

    @MainActor
    private static func sample(scene: String, phase: String) async throws {
        guard #available(iOS 27.0, *), let monitor = RUMMonitor.shared() as? Monitor,
              let handle = ProbeRuntime.sceneRegistry.handle(logicalSceneID: scene),
              let window = ProbeRuntime.sceneRegistry.window(for: handle),
              let nativeScene = window.windowScene,
              let host = window.rootViewController?.view else {
            throw FixtureError.missing("attached native scene")
        }
        for _ in 0..<100 {
            if nativeScene.activationState == .foregroundActive { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        guard nativeScene.activationState == .foregroundActive,
              let owner = monitor.rumContextSnapshot(for: .scene(.init(rawValue: handle.nativeSceneID))),
              let viewID = owner.viewID,
              monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == owner.viewID else {
            throw FixtureError.missing("active native scene and representative")
        }
        let initialTopology = try topology()
        let expectedLabels = nextPhase == 0 || nextPhase == 3 ? ["scene-A"] : ["scene-A", "scene-B"]
        guard initialTopology.map(\.logicalSceneID) == expectedLabels,
              Set(initialTopology.map(\.nativeSceneID)).count == expectedLabels.count else {
            throw FixtureError.missing("checkpoint native topology")
        }
        if nextPhase == 3 {
            guard let old = ProbeRuntime.sceneRegistry.snapshot(logicalSceneID: "scene-B"),
                  old.readiness == .disconnected,
                  !UIApplication.shared.connectedScenes.contains(where: {
                      $0.session.persistentIdentifier == old.nativeSceneID
                  }) else {
                throw FixtureError.missing("actual peer disconnect")
            }
        }
        var before = await context()
        func mapperIsReady() -> Bool {
            ProbeRuntime.eventRecorder.snapshot().contains {
                $0.kind == .rumViewSnapshot && $0.rumContext?.viewID == owner.viewID
                    && $0.rumContext?.sessionHasReplay == true && $0.rumContext?.viewActive == true
            }
        }
        for _ in 0..<100 {
            if before.0 && mapperIsReady() { break }
            try await Task.sleep(nanoseconds: 20_000_000)
            before = await context()
        }
        guard before.0 && mapperIsReady() else {
            throw FixtureError.missing("Replay enablement and independent mapper")
        }
        record("baseline-" + phase, scene: scene, native: handle.nativeSceneID,
               owner: owner, context: before, topology: initialTopology)

        // An ordinary native view mutation stimulates the real recorder.
        let stimulus = UIView(frame: CGRect(x: 30, y: 90, width: 140, height: 80))
        stimulus.backgroundColor = nextPhase.isMultiple(of: 2) ? .systemBlue : .systemOrange
        stimulus.isUserInteractionEnabled = false
        host.addSubview(stimulus)
        host.layoutIfNeeded()
        defer { stimulus.removeFromSuperview() }

        let baseline = before.1[viewID, default: 0]
        for _ in 0..<250 {
            let observed = await context()
            guard observed.0,
                  nativeScene.activationState == .foregroundActive,
                  stimulus.window === window,
                  monitor.rumContextSnapshot(for: .scene(.init(rawValue: handle.nativeSceneID)))?.viewID == owner.viewID,
                  monitor.rumContextSnapshot(for: .processRepresentative)?.viewID == owner.viewID else {
                throw FixtureError.missing("recording owner or native attachment changed")
            }
            if observed.1[viewID, default: 0] > baseline {
                let finalTopology = try topology()
                guard finalTopology.map(\.logicalSceneID) == expectedLabels,
                      finalTopology.map(\.nativeSceneID) == initialTopology.map(\.nativeSceneID) else {
                    throw FixtureError.missing("topology changed while recording")
                }
                record(phase, scene: scene, native: handle.nativeSceneID,
                       owner: owner, context: observed, topology: finalTopology)
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw FixtureError.missing("native Replay record growth")
    }
    #else
    static func configure() {}
    @MainActor
    static func capture(scene: String, phase: String) -> ProbeStepExecutionResult {
        .rejected(reason: "Replay acceptance requires the Debug fixture")
    }
    #endif
}

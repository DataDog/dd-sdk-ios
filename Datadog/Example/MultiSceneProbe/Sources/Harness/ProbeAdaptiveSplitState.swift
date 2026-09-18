/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Combine

enum ProbeAdaptiveSplitDestination: String, Hashable {
    case empty = "split-empty"
    case detailOne = "detail-1"
    case detailTwo = "detail-2"
    case placeholder

    var route: [String] { self == .empty ? [] : [rawValue] }
}

/// Application-owned accepted state; publication follows the model write.
@MainActor
final class ProbeAdaptiveSplitState: ObservableObject {
    struct Snapshot: Hashable {
        let destination: ProbeAdaptiveSplitDestination
        let generation: UInt64
    }

    @Published private(set) var current = Snapshot(destination: .empty, generation: 0)
    private let accepted = CurrentValueSubject<Snapshot, Never>(
        Snapshot(destination: .empty, generation: 0)
    )

    var publisher: AnyPublisher<Snapshot, Never> {
        accepted.eraseToAnyPublisher()
    }

    @discardableResult
    func select(_ destination: ProbeAdaptiveSplitDestination?) -> Bool {
        let destination = destination ?? .empty
        guard destination != current.destination else { return false }
        current = Snapshot(destination: destination, generation: current.generation + 1)
        accepted.send(current)
        return true
    }

    private var resizeOrdinal = 0
    private var lastResizeSequence: UInt64 = 0

    /// Consume one native resize receipt only when the current window still agrees.
    func consumeResize(
        _ signal: ProbeSignal,
        live: ProbeScenePresentation,
        logicalSceneID: String,
        nativeSceneID: String
    ) -> Int? {
        let widths = [900.0, 400.0, 900.0]
        let heights = [675.0, 700.0, 675.0]
        let classes = ["regular", "compact", "regular"]
        guard current.destination == .detailOne, current.generation == 1,
              resizeOrdinal < widths.count, signal.sequence > lastResizeSequence,
              signal.kind == .sceneGeometry, signal.evidenceSource == .probe,
              signal.semanticContext?.logicalSceneID == logicalSceneID,
              signal.semanticContext?.nativeSceneID == nativeSceneID,
              signal.navigationPath == ["detail-1"],
              signal.activationState == "foreground-active",
              live.activationState == .foregroundActive,
              signal.geometry == live.geometry,
              signal.horizontalSizeClass == live.horizontalSizeClass,
              live.geometry?.width == widths[resizeOrdinal],
              live.geometry?.height == heights[resizeOrdinal],
              live.horizontalSizeClass == classes[resizeOrdinal]
        else { return nil }
        lastResizeSequence = signal.sequence
        resizeOrdinal += 1
        return resizeOrdinal
    }

}

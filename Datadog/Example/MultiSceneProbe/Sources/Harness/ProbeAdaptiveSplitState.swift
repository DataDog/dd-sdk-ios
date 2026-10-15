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

    enum ResizeProfile {
        case duoSimulator
        case physicalIPad

        var transitions: [(width: Double, height: Double, sizeClass: String)] {
            switch self {
            case .duoSimulator:
                return [(900, 675, "regular"), (400, 700, "compact"), (900, 675, "regular")]
            case .physicalIPad:
                return [(592, 834, "compact"), (1194, 834, "regular")]
            }
        }
    }

    private var resizeOrdinal = 0
    private var lastResizeSequence: UInt64 = 0

    /// Consume one native resize receipt only when the current window still agrees.
    func consumeResize(
        _ signal: ProbeSignal,
        live: ProbeScenePresentation,
        logicalSceneID: String,
        nativeSceneID: String,
        profile: ResizeProfile = .duoSimulator
    ) -> Int? {
        let transitions = profile.transitions
        guard current.destination == .detailOne, current.generation == 1,
              resizeOrdinal < transitions.count, signal.sequence > lastResizeSequence,
              signal.kind == .sceneGeometry, signal.evidenceSource == .probe,
              signal.semanticContext?.logicalSceneID == logicalSceneID,
              signal.semanticContext?.nativeSceneID == nativeSceneID,
              signal.navigationPath == ["detail-1"],
              signal.activationState == "foreground-active",
              live.activationState == .foregroundActive,
              signal.geometry == live.geometry,
              signal.horizontalSizeClass == live.horizontalSizeClass,
              live.geometry?.width == transitions[resizeOrdinal].width,
              live.geometry?.height == transitions[resizeOrdinal].height,
              live.horizontalSizeClass == transitions[resizeOrdinal].sizeClass
        else { return nil }
        lastResizeSequence = signal.sequence
        resizeOrdinal += 1
        return resizeOrdinal
    }

}

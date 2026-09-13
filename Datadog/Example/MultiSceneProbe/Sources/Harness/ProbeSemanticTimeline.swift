/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct ProbeViewOccurrence: Hashable, Codable, CustomStringConvertible {
    let scene: String
    let screen: String
    let occurrence: Int

    var description: String {
        "\(scene)/\(screen)#\(occurrence)"
    }
}

internal struct ProbeSignalInterval: Equatable {
    let name: String
    let startSequence: UInt64
    let endSequence: UInt64?
}

internal struct ProbeSemanticEvent: Equatable {
    let kind: ProbeExpectationKind
    let signal: ProbeSignal
}

/// Pure reduction of raw harness and mapper observations into semantic events.
internal struct ProbeSemanticTimeline {
    let signals: [ProbeSignal]
    let events: [ProbeSemanticEvent]
    let viewIDsByOccurrence: [ProbeViewOccurrence: String]
    let occurrencesByViewID: [String: ProbeViewOccurrence]
    let firstViewSnapshotByID: [String: ProbeSignal]
    let intervals: [String: ProbeSignalInterval]
    let diagnostics: [String]

    init(signals: [ProbeSignal]) {
        self.signals = signals.sorted { lhs, rhs in
            if lhs.sequence == rhs.sequence {
                return lhs.timestampMilliseconds < rhs.timestampMilliseconds
            }
            return lhs.sequence < rhs.sequence
        }

        var events: [ProbeSemanticEvent] = []
        var viewIDsByOccurrence: [ProbeViewOccurrence: String] = [:]
        var occurrencesByViewID: [String: ProbeViewOccurrence] = [:]
        var firstViewSnapshotByID: [String: ProbeSignal] = [:]
        var occurrenceCounts: [String: Int] = [:]
        var observedViewIDs: Set<String> = []
        var activeByViewID: [String: Bool?] = [:]
        var documentVersionByViewID: [String: Int64] = [:]
        var openIntervals: [String: UInt64] = [:]
        var intervals: [String: ProbeSignalInterval] = [:]
        var diagnostics: [String] = []

        for signal in self.signals {
            if signal.kind == .rumViewSnapshot {
                guard let viewID = signal.rumContext?.viewID else {
                    diagnostics.append(
                        "rum-view-snapshot signal \(signal.sequence) has no RUM view ID"
                    )
                    continue
                }

                var mappedOccurrence = occurrencesByViewID[viewID]

                if
                    let context = signal.semanticContext,
                    let screen = context.screen {
                    let existingOccurrence = occurrencesByViewID[viewID]
                    let occurrence: Int
                    if let explicitOccurrence = context.occurrence {
                        occurrence = explicitOccurrence
                    } else if let existingOccurrence {
                        occurrence = existingOccurrence.occurrence
                    } else {
                        let countKey = "\(context.logicalSceneID)\u{1f}\(screen)"
                        occurrence = (occurrenceCounts[countKey] ?? 0) + 1
                    }

                    let countKey = "\(context.logicalSceneID)\u{1f}\(screen)"
                    occurrenceCounts[countKey] = max(
                        occurrenceCounts[countKey] ?? 0,
                        occurrence
                    )
                    let occurrenceKey = ProbeViewOccurrence(
                        scene: context.logicalSceneID,
                        screen: screen,
                        occurrence: occurrence
                    )
                    mappedOccurrence = occurrenceKey

                    if
                        let existingViewID = viewIDsByOccurrence[occurrenceKey],
                        existingViewID != viewID {
                        diagnostics.append(
                            "view occurrence \(occurrenceKey) maps to both "
                                + "\(existingViewID) and \(viewID)"
                        )
                    } else {
                        viewIDsByOccurrence[occurrenceKey] = viewID
                    }
                    if
                        let existingOccurrence,
                        existingOccurrence != occurrenceKey {
                        diagnostics.append(
                            "view ID \(viewID) maps to both "
                                + "\(existingOccurrence) and \(occurrenceKey)"
                        )
                    } else {
                        occurrencesByViewID[viewID] = occurrenceKey
                    }
                }

                if
                    let documentVersion = signal.rumContext?.viewDocumentVersion,
                    let previousVersion = documentVersionByViewID[viewID],
                    documentVersion < previousVersion {
                    diagnostics.append(
                        "view ID \(viewID) document version moved backwards from "
                            + "\(previousVersion) to \(documentVersion)"
                    )
                }
                if let documentVersion = signal.rumContext?.viewDocumentVersion {
                    documentVersionByViewID[viewID] = documentVersion
                }

                let isFirstSnapshot = observedViewIDs.insert(viewID).inserted
                if isFirstSnapshot {
                    firstViewSnapshotByID[viewID] = signal
                    if let mappedOccurrence {
                        openIntervals["rum-view:\(mappedOccurrence)"] = signal.sequence
                    }
                }
                let previousActive = activeByViewID[viewID] ?? nil
                let isTerminalSnapshot = signal.rumContext?.viewActive == false

                if isFirstSnapshot {
                    events.append(ProbeSemanticEvent(kind: .viewStarted, signal: signal))
                }
                if isTerminalSnapshot && (isFirstSnapshot || previousActive != false) {
                    events.append(ProbeSemanticEvent(kind: .viewStopped, signal: signal))
                    if
                        let mappedOccurrence,
                        let start = openIntervals.removeValue(
                            forKey: "rum-view:\(mappedOccurrence)"
                        ) {
                        intervals["rum-view:\(mappedOccurrence)"] = ProbeSignalInterval(
                            name: "rum-view:\(mappedOccurrence)",
                            startSequence: start,
                            endSequence: signal.sequence
                        )
                    }
                }
                activeByViewID[viewID] = signal.rumContext?.viewActive
            } else if let expectationKind = Self.semanticKind(for: signal) {
                events.append(ProbeSemanticEvent(kind: expectationKind, signal: signal))
            }

            switch signal.kind {
            case .intervalBegan:
                guard let interval = signal.interval else {
                    diagnostics.append(
                        "interval-began signal \(signal.sequence) has no interval name"
                    )
                    continue
                }
                if openIntervals[interval] != nil {
                    diagnostics.append("interval \(interval) began more than once")
                }
                openIntervals[interval] = signal.sequence
            case .intervalEnded:
                guard let interval = signal.interval else {
                    diagnostics.append(
                        "interval-ended signal \(signal.sequence) has no interval name"
                    )
                    continue
                }
                guard let start = openIntervals.removeValue(forKey: interval) else {
                    diagnostics.append("interval \(interval) ended without beginning")
                    continue
                }
                intervals[interval] = ProbeSignalInterval(
                    name: interval,
                    startSequence: start,
                    endSequence: signal.sequence
                )
            default:
                break
            }
        }

        for (name, start) in openIntervals {
            intervals[name] = ProbeSignalInterval(
                name: name,
                startSequence: start,
                endSequence: nil
            )
        }

        self.events = events
        self.viewIDsByOccurrence = viewIDsByOccurrence
        self.occurrencesByViewID = occurrencesByViewID
        self.firstViewSnapshotByID = firstViewSnapshotByID
        self.intervals = intervals
        self.diagnostics = diagnostics
    }

    func viewID(
        scene: String,
        screen: String,
        occurrence: Int
    ) -> String? {
        viewIDsByOccurrence[
            ProbeViewOccurrence(
                scene: scene,
                screen: screen,
                occurrence: occurrence
            )
        ]
    }

    func observedScene(for signal: ProbeSignal) -> String? {
        signal.semanticContext?.logicalSceneID
            ?? occurrence(for: signal)?.scene
    }

    func observedScreen(for signal: ProbeSignal) -> String? {
        signal.semanticContext?.screen
            ?? occurrence(for: signal)?.screen
    }

    func observedOccurrence(for signal: ProbeSignal) -> Int? {
        signal.semanticContext?.occurrence
            ?? occurrence(for: signal)?.occurrence
    }

    func rumViewOrigin(for signal: ProbeSignal) -> ProbeRUMViewOrigin? {
        guard
            let viewID = signal.rumContext?.viewID,
            let firstSnapshot = firstViewSnapshotByID[viewID],
            firstSnapshot.sequence <= signal.sequence
        else {
            return nil
        }
        if occurrencesByViewID[viewID] != nil {
            return .semantic
        }
        guard firstSnapshot.rumContext?.viewName != "ApplicationLaunch" else {
            return nil
        }
        return .automatic
    }

    func ownerView(
        for signal: ProbeSignal,
        startedAfterOpening scene: String
    ) -> Bool {
        guard
            let viewID = signal.rumContext?.viewID,
            let firstSnapshot = firstViewSnapshotByID[viewID],
            firstSnapshot.sequence <= signal.sequence,
            let openStep = signals.last(where: {
                $0.sequence < signal.sequence
                    && $0.kind == .stepStarted
                    && $0.stepKind == .openWindow
                    && $0.name == scene
            })
        else {
            return false
        }
        return firstSnapshot.sequence > openStep.sequence
    }

    func ownerViewRelation(
        for signal: ProbeSignal,
        toActionNamed actionName: String
    ) -> ProbeRUMViewOwnerRelation? {
        guard
            let ownerViewID = signal.rumContext?.viewID,
            let referenceAction = signals.last(where: {
                $0.sequence < signal.sequence
                    && $0.kind == .rumAction
                    && $0.name == actionName
            }),
            let referenceViewID = referenceAction.rumContext?.viewID
        else {
            return nil
        }
        return ownerViewID == referenceViewID ? .same : .different
    }

    func ownerView(
        for signal: ProbeSignal,
        startedAfter stepKind: ProbeStepKind,
        value stepValue: String?
    ) -> Bool {
        guard
            let viewID = signal.rumContext?.viewID,
            let firstSnapshot = firstViewSnapshotByID[viewID],
            firstSnapshot.sequence <= signal.sequence,
            let step = signals.last(where: {
                $0.sequence < signal.sequence
                    && $0.kind == .stepStarted
                    && $0.stepKind == stepKind
                    && (stepValue == nil || $0.name == stepValue)
            })
        else {
            return false
        }
        return firstSnapshot.sequence > step.sequence
    }

    func events(in interval: String?) -> [ProbeSemanticEvent]? {
        guard let interval else {
            return events
        }
        guard
            let bounds = intervals[interval],
            let endSequence = bounds.endSequence
        else {
            return nil
        }
        return events.filter {
            $0.signal.sequence > bounds.startSequence
                && $0.signal.sequence < endSequence
        }
    }

    private func occurrence(for signal: ProbeSignal) -> ProbeViewOccurrence? {
        guard let viewID = signal.rumContext?.viewID else {
            return nil
        }
        return occurrencesByViewID[viewID]
    }

    private static func semanticKind(
        for signal: ProbeSignal
    ) -> ProbeExpectationKind? {
        switch signal.kind {
        case .sceneReady:
            return .sceneReady
        case .sceneLifecycle where signal.scenePhase == "disconnected":
            return .sceneDisconnected
        case .transitionBegan:
            return .transitionBegan
        case .transitionResolved:
            return .transitionResolved
        case .destinationMaterialized:
            return .destinationMaterialized
        case .rumAction:
            return .action
        case .rumResource:
            return .resource
        case .rumError:
            return .error
        case .rumTrace:
            return .trace
        case .rumOperation:
            return .operationStep
        default:
            return nil
        }
    }
}

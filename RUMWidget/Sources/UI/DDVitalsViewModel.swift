/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
import DatadogInternal
import DatadogRUM
import Observation
import SwiftUI
import Foundation

@available(iOS 15.0, *)
public final class DDVitalsViewModel: ObservableObject {
    @Published var progress: CGFloat = 0 // Value between 0.0 and 1.0

    @Published var rumEvents: [TimelineEvent] = []

    @Published var cpuValue: Int = 0
    @Published var memoryValue: Int = 0
    @Published var threadsCount: Int = 0

    var hitchesRatio: CGFloat {
//        lastHitchValue = hitchesDuration / currentDuration * Double(1.toMilliseconds)
        return hitchesDuration / currentDuration * Double(1.toMilliseconds)
    } // milliseconds/second
    var hangsRatio: CGFloat { hangsDuration / currentDuration * 1.hours } // seconds/hour

    var currentDuration: CGFloat = 0.1

    private var viewMaxDuration = 60.0

    private var rumFeature: RUMFeature? { CoreRegistry.default.get(feature: RUMFeature.self) }

    private weak var activeViewScope: RUMViewScope?

//    private var lastHitchValue: CGFloat = 0
//    private var hitchesDictionary: [String: [CGFloat]] = [:]

    public init() {
    }

    func updateView() {
        guard let viewScope = rumFeature?.activeView else { return }

        if activeViewScope == nil || activeViewScope !== viewScope {
            //hitchesDictionary[activeViewScope?.viewName ?? ""] = hitchesDictionary[activeViewScope?.viewName ?? "", default: []] + [lastHitchValue]

            viewMaxDuration = 60.0
            rumEvents = []
            progress = 1/viewMaxDuration

            print("****\(activeViewScope)****\(viewScope)*************************************************************** \(viewScope.timeSpent)")
        }

        activeViewScope = viewScope

        updateTimeline(viewScope: viewScope)
        updateVitals(viewScope: viewScope)
    }

    func updateTimeline(viewScope: RUMViewScope) {
        if viewScope.timeSpent > 0 {

            let viewHitches = viewScope.viewHitches ?? []
            currentDuration = viewScope.timeSpent

            progress = min(currentDuration / viewMaxDuration, 1)
            if currentDuration > viewMaxDuration {
                viewMaxDuration = currentDuration
            }

            var events: [TimelineEvent] = []
            for (index, scope) in viewScope.resourceEvents.enumerated() {
                events.append(TimelineEvent(id: index,
                                            start: scope.0 / viewMaxDuration,
                                            duration: scope.1 < 1 ? 1 : scope.1, event: .resource))
            }

            for scope in viewScope.userEvents {
                events.append(TimelineEvent(id: events.count + 1,
                                            start: scope.0 / viewMaxDuration,
                                            duration: scope.1 < 1 ? 1 : scope.1, event: .userAction))
            }

            for hitch in viewHitches {
                let start = Double(hitch.start) / 1_000_000_000.0
                let duration = Double(hitch.duration) / 1_000_000_000.0
                events.append(TimelineEvent(id: events.count + 1, start: start / viewMaxDuration, duration: duration < 1 ? 1 : duration, event: .viewHitch))
            }

            for hang in viewScope.hangs {
                let start = Double(hang.0)
                let duration = Double(hang.1)
                events.append(TimelineEvent(id: events.count + 1, start: start / viewMaxDuration, duration: duration < 1 ? 1 : duration, event: .appHang))
            }

            self.rumEvents = events
        }
    }

    func updateVitals(viewScope: RUMViewScope) {
        cpuValue = Int(Vitals.cpuUsage())
        memoryValue = Int((viewScope.memoryValue ?? 0).MB)
        threadsCount = Vitals.countThreads()
    }

    var hitchesDuration: Double {
        activeViewScope?.hitchesDuration ?? 0
    }

    var hangsDuration: Double {
        (activeViewScope?.totalAppHangDuration ?? 0)
    }

    var viewScopeName: String {
        if let viewName = activeViewScope?.viewName.split(separator: ".").last {
            return String(viewName)
        }

        return "Unknown"
    }
}

@available(iOS 15.0, *)
extension DDVitalsViewModel {
    func levelFor(cpu: Int) -> WarningLevel {
        switch cpu {
        case ..<80:
            .low
        case ..<100:
            .medium
        default:
            .high
        }
    }

    func levelFor(memory: Int) -> WarningLevel {
        switch memory {
        case ..<300:
            .low
        case ..<500:
            .medium
        default:
            .high
        }
    }

    func levelFor(threads: Int) -> WarningLevel {
        switch threads {
        case ...ProcessInfo.processInfo.processorCount:
            .low
        case ...(ProcessInfo.processInfo.processorCount * 2):
            .medium
        default:
            .high
        }
    }
}

private extension Double {
    var MB: Self { self / 1_000_000 }
}

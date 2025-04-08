/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Observation
import SwiftUI

@available(iOS 15.0, *)
public final class DDVitalsViewModel: ObservableObject {
    @Published var progress: CGFloat = 0 // Value between 0.0 and 1.0
    @Published var hangs: [(CGFloat, CGFloat)] = [] // Range for green highlight (e.g., 0.2...0.3)
    @Published var hitches: [(CGFloat, CGFloat)] = [] // Positions of vertical lines (e.g., [0.6, 0.7, 0.75])

    @Published var cpuValue: Double = 0
    @Published var memoryValue: Double = 0

    var hitchesRatio: CGFloat {
        lastHitchValue = hitchesDuration / currentDuration * Double(1.toMilliseconds)
        return lastHitchValue
    } // milliseconds/second
    var hangsRatio: CGFloat { hangsDuration / currentDuration * 1.hours } // seconds/hour

    private var startTimestamp: CGFloat?

    var currentDuration: CGFloat = 0.1

    private var viewMaxDuration = 60.0

    private let rumFeature: RUMFeature?
    let metricsManager: DatadogMetricSubscriber

    private var activeViewScope: RUMViewScope?

    private var lastHitchValue: CGFloat = 0
    private var hitchesDictionary: [String: [CGFloat]] = [:]

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default,
        metricsManager: DatadogMetricSubscriber = DatadogMetricSubscriber(core: CoreRegistry.default)
    ) {
        rumFeature = core.get(feature: RUMFeature.self)
        self.metricsManager = metricsManager
    }

    func updateView() {
        guard let viewScope = rumFeature?.monitor.scopes.activeSession?.viewScopes.first(where: { $0.isActiveView }) else { return }

        if activeViewScope !== viewScope {
            hitchesDictionary[activeViewScope?.viewName ?? ""] = hitchesDictionary[activeViewScope?.viewName ?? "", default: []] + [lastHitchValue]

            viewMaxDuration = 60.0
            hitches = []
            hangs = []
            progress = 0
        }

        activeViewScope = viewScope

        updateTimeline(viewScope: viewScope)
        updateVitals(viewScope: viewScope)
    }

    func updateTimeline(viewScope: RUMViewScope) {
        if let viewHitches = getViewHitches(from: viewScope),
           viewHitches.dataModel.startTimestamp > 0 {
            startTimestamp = viewHitches.dataModel.startTimestamp

            let interval = CACurrentMediaTime() - startTimestamp!
            currentDuration = interval

            progress = interval / viewMaxDuration
            if progress >= 1.0 {
                withAnimation { viewMaxDuration = interval }
            }

            if progress > 500 {
                print("\(startTimestamp)")
            }

            hitches = viewHitches.dataModel.hitches.map {
                let start = Double($0.start) / 1_000_000_000.0
                let duration = Double($0.duration) / 1_000_000_000.0
                // print("\(start / viewDuration) - \(duration)")
                return (start / viewMaxDuration, CGFloat(duration < 1 ? 1 : duration))
            }
        }

        for hang in viewScope.hangs {
            hangs.append((hang.0 / viewMaxDuration, hang.1))
        }
    }

    func updateVitals(viewScope: RUMViewScope) {
        guard let vitalInfoSampler = viewScope.vitalInfoSampler else { return }

        cpuValue = (vitalInfoSampler.cpu.currentValue ?? 0) / 1_000
        memoryValue = (vitalInfoSampler.memory.currentValue ?? 0).MB

        print("CPU: \(vitalInfoSampler.cpu)")
        print("Memory: \(vitalInfoSampler.memory)")
    }

    func getViewHitches(from viewScope: RUMViewScope) -> ViewHitchesModel? { viewScope.viewHitchesReader }

    var hitchesDuration: Double {
        (activeViewScope?.viewHitchesReader?.dataModel.hitchesDuration ?? 0)
    }

    var hangsDuration: Double {
        (activeViewScope?.totalAppHangDuration ?? 0)
    }

    var viewScopeName: String {
        activeViewScope?.viewName ?? "Unknown"
    }
}

private extension Double {
    var MB: Self { self / 1_000_000 }
}

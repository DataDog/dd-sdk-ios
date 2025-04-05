//
//  ViewHitchesViewModel.swift
//  Shopist
//
//  Created by Simao Seica on 02/03/2025.
//  Copyright © 2025 Shopist. All rights reserved.
//

import SwiftUI
import Observation
import DatadogInternal

@available(iOS 15.0, *)
public final class ViewHitchesViewModel: ObservableObject {

    @Published var progress: CGFloat = 0 // Value between 0.0 and 1.0
    @Published var hangs: [(CGFloat, CGFloat)] = [] // Range for green highlight (e.g., 0.2...0.3)
    @Published var hitches: [(CGFloat, CGFloat)] = [] // Positions of vertical lines (e.g., [0.6, 0.7, 0.75])

    var hitchesRatio: CGFloat {

        lastHitchValue = hitchesDuration / currentDuration * Double(1.toMilliseconds)
        return lastHitchValue
    } // milliseconds/second
    var hangsRatio: CGFloat { hangsDuration / currentDuration * 1.hours } // seconds/hour

    private var startTimestamp: CGFloat?

    var currentDuration: CGFloat = 0.1

    private var viewMaxDuration = 60.0

    private let rumFeature: RUMFeature
    let metricsManager: DatadogMetricSubscriber

    private var activeViewScope: RUMViewScope?

    private var lastHitchValue: CGFloat = 0
    private var hitchesDictionary: [String: [CGFloat]] = [:]

    public init (
        core: DatadogCoreProtocol = CoreRegistry.default,
        metricsManager: DatadogMetricSubscriber = DatadogMetricSubscriber(core: CoreRegistry.default)
    ) {

        self.rumFeature = core.get(feature: RUMFeature.self)!
        self.metricsManager = metricsManager
    }

    func updateTimeline() {

        guard let viewScope = rumFeature.monitor.scopes.activeSession?.viewScopes.first(where: { $0.isActiveView }) else { return }

        if activeViewScope !== viewScope {

            hitchesDictionary[activeViewScope?.viewName ?? ""] = hitchesDictionary[activeViewScope?.viewName ?? "", default: []] + [lastHitchValue]
            print("*********************New view scope*****************+")
            print("Slow Frame Rate:\(hitchesDictionary[activeViewScope?.viewName ?? ""])")

            viewMaxDuration = 60.0
            hitches = []
            hangs = []
            progress = 0
        }
        self.activeViewScope = viewScope

        if let viewHitches = self.getViewHitches(from: viewScope),
           viewHitches.dataModel.startTimestamp > 0 {

            self.startTimestamp = viewHitches.dataModel.startTimestamp

            let interval = CACurrentMediaTime() - self.startTimestamp!
            currentDuration = interval

            progress = interval / viewMaxDuration
            if progress >= 1.0 {

                withAnimation { viewMaxDuration = interval }
            }

            if progress > 500 {

                print("\(self.startTimestamp)")
            }

            hitches = viewHitches.dataModel.hitches.map {

                let start = Double($0.start) / 1_000_000_000.0
                let duration = Double($0.duration) / 1_000_000_000.0
                //print("\(start / viewDuration) - \(duration)")
                return (start / viewMaxDuration, CGFloat(duration < 1 ? 1 : duration))
            }
        } else {

//            viewMaxDuration = 60.0
//            hitches = []
//            hangs = []
//            progress = 0
        }

        for hang in viewScope.hangs {

            self.hangs.append((hang.0 / viewMaxDuration, hang.1))
        }
    }

    func getViewHitches(from viewScope: RUMViewScope) -> ViewHitchesModel? { viewScope.viewHitchesReader }

    var hitchesDuration: Double {

        return (activeViewScope?.viewHitchesReader?.dataModel.hitchesDuration ?? 0)
    }

    var hangsDuration: Double {

        return (activeViewScope?.totalAppHangDuration ?? 0)
    }

    var viewScopeName: String {

        return activeViewScope?.viewName ?? "Unknown"
    }
}

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
public final class AppLaunchViewModel: ObservableObject {
    @Published var ttid: Double = 0.0 //ms
    @Published var ttfd: Double = 0.0 //ms

    @Published var rumEvents: [AppEvent] = []

    @Published var launchReason: String = ""
    @Published var launchDetails: String = ""

    var currentDuration: CGFloat = 0.1
    let timelineMaxDuration = 3.0
    let zoom = 1.0

    private var rumFeature: RUMFeature? { CoreRegistry.default.get(feature: RUMFeature.self) }

    private weak var activeViewScope: RUMViewScope?

    public init() {
    }

    func updateView() {
        guard let viewScope = rumFeature?.activeView else { return }

        if activeViewScope == nil || activeViewScope !== viewScope {
            //hitchesDictionary[activeViewScope?.viewName ?? ""] = hitchesDictionary[activeViewScope?.viewName ?? "", default: []] + [lastHitchValue]

        }

        activeViewScope = viewScope
        currentDuration = viewScope.timeSpent

        launchReason = viewScope.launchReason ?? ""

        guard let sessionScope = rumFeature?.activeSession else { return }

        ttid = sessionScope.startUpTime ?? 0.0
        if let ttfd = viewScope.ttfd {
            self.ttfd = ttid < ttfd ? ttfd : ttid
        }

        PreMainHelper.recordFirstFrame(sessionScope.ttidDate)
        PreMainHelper.recordFullDisplay(viewScope.ttfdDate)
        if let info = PreMainHelper.info {
            launchDetails = info.displayDescription
            updateTimeline(info)
        }
    }

    func updateTimeline(_ info: PreMainInfo) {
        var events: [AppEvent] = []

        events.append(AppEvent(id: .load, text: info.loadString, width: 3, start: info.processToLoad / timelineMaxDuration - 0.5))
        events.append(AppEvent(id: .attribute101, text: info.attribute101String, start: info.processBootstrap / timelineMaxDuration - 0.5))
        events.append(AppEvent(id: .attribute50000, text: info.attribute65000String, start: info.processBootstrap2 / timelineMaxDuration - 0.5))
        events.append(AppEvent(id: .main, text: info.mainString, start: info.mainInitialization / timelineMaxDuration - 0.5))
        events
            .append(AppEvent(id: .didFinishLaunching, text: info.didFinishLaunchingString, start: info.didFinishLaunching / timelineMaxDuration - 0.5))
        events.append(AppEvent(id: .ttid, text: info.ttidString, width: 3, start: info.ttid / timelineMaxDuration - 0.5))
        events.append(AppEvent(id: .ttfd, text: info.ttfdString, width: 3, start: ttfd / timelineMaxDuration - 0.5))
        self.rumEvents = events
    }

    var viewScopeName: String {
        if let viewName = activeViewScope?.viewName.split(separator: ".").last {
            return String(viewName)
        }

        return "Unknown"
    }
}

@available(iOS 15.0, *)
extension AppLaunchViewModel {
    func levelFor(startup: Double) -> WarningLevel {
        switch startup {
        case ...3.0:
            .low
        case ...5.0:
            .medium
        default:
            .high
        }
    }
}

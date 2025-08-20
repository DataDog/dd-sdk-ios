/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Tells if data upload can be performed based on given system conditions.
internal struct DataUploadConditions {
    enum Blocker {
        case constrainedNetworkAccess
        case battery(level: Int, state: BatteryStatus.State)
        case lowPowerModeOn
        case networkReachability(description: String)
    }

    struct Constants {
        /// Battery level above which data upload can be performed.
        static let minBatteryLevel: Float = 0.1
    }

    /// Battery level above which data upload can be performed.
    let minBatteryLevel: Float

    /// Blocks uploads on networks with "Low Data Mode" enabled when set to `false`. Defaults to `true`.
    let allowsConstrainedNetworkAccess: Bool

    init(minBatteryLevel: Float = Constants.minBatteryLevel, allowsConstrainedNetworkAccess: Bool = true) {
        self.minBatteryLevel = minBatteryLevel
        self.allowsConstrainedNetworkAccess = allowsConstrainedNetworkAccess
    }

    func blockersForUpload(with context: DatadogContext) -> [Blocker] {
        var blockers: [Blocker] = []
        #if !os(watchOS)
        guard let reachability = context.networkConnectionInfo?.reachability else {
            // when `NetworkConnectionInfo` is not yet available
            return [.networkReachability(description: "unknown")]
        }
        let networkIsReachable = reachability == .yes || reachability == .maybe
        if !networkIsReachable {
            blockers = [.networkReachability(description: reachability.rawValue)]
        }
        if let isConstrained = context.networkConnectionInfo?.isConstrained, isConstrained, !allowsConstrainedNetworkAccess {
            return [.allowsConstrainedNetworkAccessFalse]
        }
        #endif

        guard let battery = context.batteryStatus, battery.state != .unknown else {
            // Note: in RUMS-132 we got the report on `.unknown` battery state reporing `-1` battery level on iPad device
            // plugged to Mac through lightning cable. As `.unkown` may lead to other unreliable values,
            // it seems safer to arbitrary allow uploads in such case.
            return blockers
        }

        let batteryFullOrCharging = battery.state == .full || battery.state == .charging
        let batteryLevelIsEnough = battery.level > minBatteryLevel

        if !(batteryFullOrCharging || batteryLevelIsEnough) {
            blockers.append(
                .battery(
                    level: Int(battery.level * 100),
                    state: battery.state
                )
            )
        }

        if context.isLowPowerModeEnabled {
            blockers.append(.lowPowerModeOn)
        }

        return blockers
    }
}

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Tells if data upload can be performed based on given system conditions.
internal struct DataUploadConditions {
    enum Blocker {
        case batteryLevel
        case lowPowerModeOn
        case networkCondition
    }

    enum Report {
        case go
        case noGo(blockers: Set<Blocker>)

        static func && (lhs: Report, rhs: Report) -> Report {
            switch (lhs, rhs) {
            case (.go, .go):
                return .go
            case (.go, .noGo):
                return rhs
            case (.noGo, .go):
                return lhs
            case (let .noGo(blockers: lbs), let .noGo(blockers: rbs)):
                return .noGo(blockers: lbs.union(rbs))
            }
        }
    }

    struct Constants {
        /// Battery level above which data upload can be performed.
        static let minBatteryLevel: Float = 0.1
    }

    let batteryStatus: BatteryStatusProviderType?
    let networkConnectionInfo: NetworkConnectionInfoProviderType

    func canPerformUpload() -> Report {
        let batteryStatus = self.batteryStatus?.current
        guard let networkConnectionInfo = self.networkConnectionInfo.current else {
            return .noGo(blockers: [.networkCondition]) // when `NetworkConnectionInfo` is not yet available
        }

        if let batteryStatus = batteryStatus {
            return canUploadWith(networkConnectionInfo) && canUploadWith(batteryStatus)
        } else {
            return canUploadWith(networkConnectionInfo)
        }
    }

    private func canUploadWith(_ batteryStatus: BatteryStatus) -> Report {
        let state = batteryStatus.state
        if state == .unknown {
            // Note: in RUMS-132 we got the report on `.unknown` battery state reporing `-1` battery level on iPad device
            // plugged to Mac through lightning cable. As `.unkown` may lead to other unreliable values,
            // it seems safer to arbitrary allow uploads in such case.
            return .go
        }

        var blockers = Set<Blocker>()
        let batteryFullOrCharging = state == .full || state == .charging
        let batteryLevelIsEnough = batteryStatus.level > Constants.minBatteryLevel
        if !(batteryFullOrCharging || batteryLevelIsEnough) {
            blockers.insert(.batteryLevel)
        }

        if batteryStatus.isLowPowerModeEnabled {
            blockers.insert(.lowPowerModeOn)
        }

        return blockers.count == 0 ? .go : .noGo(blockers: blockers)
    }

    private func canUploadWith(_ networkConnectionInfo: NetworkConnectionInfo) -> Report {
        let networkIsReachable = networkConnectionInfo.reachability == .yes || networkConnectionInfo.reachability == .maybe
        return networkIsReachable ? .go : .noGo(blockers: [.networkCondition])
    }
}

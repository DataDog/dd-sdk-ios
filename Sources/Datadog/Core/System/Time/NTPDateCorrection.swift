/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Adjusts device time to server time using the time difference calculated with NTP.
internal protocol NTPDateCorrectionType {
    /// Corrects given device time to server time using the last known time difference between the two.
    func toServerDate(deviceDate: Date) -> Date
}

internal class NTPDateCorrection: NTPDateCorrectionType {
    func toServerDate(deviceDate: Date) -> Date {
        return deviceDate
    }
}

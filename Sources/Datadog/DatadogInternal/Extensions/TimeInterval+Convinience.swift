/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An extension for TimeInterval that provides a more semantic and expressive
/// API for converting time representations into TimeInterval's default unit: seconds.
public extension TimeInterval {
    /// A helper property that returns the current value as a direct representation in seconds.
    var seconds: TimeInterval { return TimeInterval(self) }

    /// A property that converts the given number of minutes into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var minutes: TimeInterval { return self.multiplyOrClamp(by: 60) }

    /// A property that converts the given number of hours into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var hours: TimeInterval { return self.multiplyOrClamp(by: 60.minutes) }

    /// A property that converts the given number of days into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var days: TimeInterval { return self.multiplyOrClamp(by: 24.hours) }

    /// A private helper method for multiplying the TimeInterval value by a factor
    /// and clamping the result to prevent overflow. If the multiplication results in
    /// overflow, the greatest finite magnitude value of TimeInterval is returned.
    ///
    /// - Parameter factor: The multiplier to apply to the time interval.
    /// - Returns: The multiplied time interval, clamped to the greatest finite magnitude if necessary.
    private func multiplyOrClamp(by factor: TimeInterval) -> TimeInterval {
        guard factor != 0 else {
            return 0
        }
        let multiplied = TimeInterval(self) * factor
        if multiplied / factor != TimeInterval(self) {
            return TimeInterval.greatestFiniteMagnitude
        }
        return multiplied
    }
}

/// An extension for FixedWidthInteger that provides a more semantic and expressive
/// API for converting time representations into TimeInterval's default unit: seconds.
public extension FixedWidthInteger {
    /// A helper property that returns the current value as a direct representation in seconds.
    var seconds: TimeInterval { return TimeInterval(self) }

    /// A property that converts the given numeric value of minutes into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var minutes: TimeInterval {
        let (result, overflow) = self.multipliedReportingOverflow(by: 60)
        return overflow ? TimeInterval.greatestFiniteMagnitude : TimeInterval(result)
    }

    /// A property that converts the given numeric value of hours into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var hours: TimeInterval {
        let (result, overflow) = self.multipliedReportingOverflow(by: Self(60.minutes))
        return overflow ? TimeInterval.greatestFiniteMagnitude : TimeInterval(result)
    }

    /// A property that converts the given numeric value of days into seconds.
    /// In case of overflow, TimeInterval.greatestFiniteMagnitude is returned.
    var days: TimeInterval {
        let (result, overflow) = self.multipliedReportingOverflow(by: Self(24.hours))
        return overflow ? TimeInterval.greatestFiniteMagnitude : TimeInterval(result)
    }
}

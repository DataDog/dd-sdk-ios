/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

/// Crash Report format supported by Datadog SDK.
public struct DDCrashReport {
    /// The date of the crash occurrence.
    internal let crashDate: Date?
    /// E.g. ... TODO - fill in
    internal let signalCode: String?
    /// E.g. ... TODO - fill in
    internal let signalName: String?
    /// E.g. ... TODO - fill in
    internal let signalDetails: String?
    /// E.g. ... TODO - fill in
    internal let stackTrace: String?

    public init(
        crashDate: Date?,
        signalCode: String?,
        signalName: String?,
        signalDetails: String?,
        stackTrace: String?
    ) {
        self.crashDate = crashDate
        self.signalCode = signalCode
        self.signalName = signalName
        self.signalDetails = signalDetails
        self.stackTrace = stackTrace
    }
}

/// An interface for enabling crash reporting feature in Datadog SDK.
/// It is implemented by `DDCrashReportingPlugin` from `DatadogCrashReporting` framework.
public protocol DDCrashReportingPluginType: class {
    /// Reads unprocessed crash report if available.
    /// - Parameter completion: the completion block called with the value of `DDCrashReport` if a crash report is available
    /// or with `nil` otherwise. The value returned by the receiver should indicate if the crash report was processed correctly (`true`)
    /// or something went wrong (`false)`. Depending on the returned value, the crash report will be purged or perserved for future read.
    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool)
}

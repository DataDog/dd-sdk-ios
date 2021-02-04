/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import Datadog

extension CrashReportingFeature {
    static func mockWith(
        configuration: FeaturesConfiguration.CrashReporting = .mockAny()
    ) -> CrashReportingFeature {
        return CrashReportingFeature(configuration: configuration)
    }
}

internal class CrashReportingPluginMock: DDCrashReportingPluginType {
    /// The crash report loaded by this plugin.
    var pendingCrashReport: DDCrashReport?
    /// If the plugin was asked to delete the crash report.
    var hasPurgedCrashReport: Bool?

    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        hasPurgedCrashReport = completion(pendingCrashReport)
    }
}

extension DDCrashReport: EquatableInTests {}

internal extension DDCrashReport {
    static func mockRandom() -> DDCrashReport {
        return mockWith(
            crashDate: .mockRandomInThePast(),
            signalCode: .mockRandom(),
            signalName: .mockRandom(),
            signalDetails: .mockRandom(),
            stackTrace: .mockRandom()
        )
    }

    static func mockWith(
        crashDate: Date? = .mockAny(),
        signalCode: String? = .mockAny(),
        signalName: String? = .mockAny(),
        signalDetails: String? = .mockAny(),
        stackTrace: String? = .mockAny()
    ) -> DDCrashReport {
        return DDCrashReport(
            crashDate: crashDate,
            signalCode: signalCode,
            signalName: signalName,
            signalDetails: signalDetails,
            stackTrace: stackTrace
        )
    }
}

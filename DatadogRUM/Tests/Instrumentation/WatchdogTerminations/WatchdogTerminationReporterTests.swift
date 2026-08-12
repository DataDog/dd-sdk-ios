/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM
import TestUtilities

final class WatchdogTerminationReporterTests: XCTestCase {
    let featureScope = FeatureScopeMock()

    func testSend_sanitizesRUMErrorContextBeforeWriting() throws {
        let numberOfAttributes = AttributesSanitizer.Constraints.maxNumberOfAttributes * 2

        // Given
        var viewEvent: RUMViewEvent = .mockRandomWith(crashCount: 0)
        viewEvent.context = RUMEventAttributes(
            contextInfo: Dictionary(uniqueKeysWithValues: (0..<numberOfAttributes).map { ("attribute-\($0)", String.mockAny() as Encodable) })
        )

        let reporter = WatchdogTerminationReporter(
            featureScope: featureScope,
            dateProvider: DateProviderMock(),
            uuidGenerator: RUMUUIDGeneratorMock()
        )

        // When
        reporter.send(
            date: Date(timeIntervalSinceReferenceDate: TimeInterval(viewEvent.date)),
            state: .mockWith(trackingConsent: .granted),
            viewEvent: viewEvent
        )

        // Then
        let sentRUMError = try XCTUnwrap(featureScope.eventsWritten(ofType: RUMErrorEvent.self).first)
        let usrInfoCount = sentRUMError.usr?.usrInfo.count ?? 0
        let accountInfoCount = sentRUMError.account?.accountInfo.count ?? 0
        let contextInfoCount = sentRUMError.context?.contextInfo.count ?? 0
        XCTAssertEqual(usrInfoCount + accountInfoCount + contextInfoCount, AttributesSanitizer.Constraints.maxNumberOfAttributes)
        XCTAssertEqual(contextInfoCount, AttributesSanitizer.Constraints.maxNumberOfAttributes - usrInfoCount - accountInfoCount, "`contextInfo` is removed first, then `account`, when the total exceeds the limit")
    }
}

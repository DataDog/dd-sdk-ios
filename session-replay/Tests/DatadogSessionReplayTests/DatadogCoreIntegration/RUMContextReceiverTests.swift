/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable empty_xctest_method
class RUMContextReceiverTests: XCTestCase {
    private let receiver = RUMContextReceiver()

    func testWhenMessageContainsNonEmptyRUMBaggage_itNotifiesRUMContext() {
        // TODO: RUMM-2690
        // Implementing this test requires creating partial mocks for `FeatureMessage` and `DatadogContext`,
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenMessageContainsEmptyRUMBaggage_itNotifiesNoRUMContext() {
        // TODO: RUMM-2690
        // Implementing this test requires creating partial mocks for `FeatureMessage` and `DatadogContext`,
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenSucceedingMessagesContainDifferentRUMBaggages_itNotifiesRUMContextChange() {
        // TODO: RUMM-2690
        // Implementing this test requires creating partial mocks for `FeatureMessage` and `DatadogContext`,
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenSucceedingMessagesContainEqualRUMBaggages_itDoesNotNotifyRUMContextChange() {
        // TODO: RUMM-2690
        // Implementing this test requires creating partial mocks for `FeatureMessage` and `DatadogContext`,
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }
}
// swiftlint:enable empty_xctest_method

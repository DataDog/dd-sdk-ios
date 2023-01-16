/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Datadog
@testable import DatadogSessionReplay
@testable import TestUtilities

// swiftlint:disable empty_xctest_method
class RequestBuilderTests: XCTestCase {
    func testWhenCustomUploadURLIsNotSet_itCreatesRequestsToAppropriateDatadogSite() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureRequestBuilder`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenCustomUploadURLIsSet_itCreatesRequestsToCustomURL() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureRequestBuilder`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenBatchContainsRecordsFromOneSegment_itCreatesOneRequest() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureRequestBuilder`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenBatchContainsRecordsFromMultipleSegments_itCreatesMultipleRequests() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureRequestBuilder`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }

    func testWhenBatchDataIsMalformed_itThrows() {
        // TODO: RUMM-2690
        // Implementing this test requires creating mocks for `DatadogContext` (passed in `FeatureRequestBuilder`),
        // which is yet not possible as we lack separate, shared module to facilitate tests.
    }
}
// swiftlint:enable empty_xctest_method

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal
import DatadogSessionReplay

internal class MockFeature: DatadogRemoteFeature {
    static var name = "mock-feature"

    var requestBuilder: FeatureRequestBuilder = MockRequestBuilder()
}

internal class MockRequestBuilder: FeatureRequestBuilder {
    func request(for events: [DatadogInternal.Event], with context: DatadogInternal.DatadogContext) throws -> URLRequest {
        URLRequest.mockAny()
    }
}
#endif

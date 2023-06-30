/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import Datadog

extension PerformancePreset {
    static let benchmarksPreset = PerformancePreset(batchSize: .small, uploadFrequency: .frequent, bundleType: .iOSApp)
}

struct FeatureRequestBuilderMock: FeatureRequestBuilder {
    let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    func request(for events: [Event], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(
            url: .mockAny(),
            queryItems: [.ddtags(tags: ["foo:bar"])],
            headers: []
        )

        let data = dataFormat.format(events.map { $0.data })
        return builder.uploadRequest(with: data)
    }
}

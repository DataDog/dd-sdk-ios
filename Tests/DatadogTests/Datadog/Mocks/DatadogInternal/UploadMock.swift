/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

@testable import Datadog

internal struct FeatureRequestBuilderMock: FeatureRequestBuilder {
    let url: URL
    let queryItems: [URLRequestBuilder.QueryItem]
    let headers: [URLRequestBuilder.HTTPHeader]
    let format: DataFormat

    init(
        url: URL = .mockAny(),
        queryItems: [URLRequestBuilder.QueryItem] = [],
        headers: [URLRequestBuilder.HTTPHeader] = [],
        format: DataFormat = .mockWith(prefix: "[", suffix: "]", separator: ",")
    ) {
        self.url = url
        self.queryItems = queryItems
        self.headers = headers
        self.format = format
    }

    func request(for events: [Data], with context: DatadogContext) -> URLRequest {
        let builder = URLRequestBuilder(url: url, queryItems: queryItems, headers: headers)
        let data = format.format(events)
        return builder.uploadRequest(with: data)
    }
}

extension URLRequestBuilder.QueryItem: RandomMockable, AnyMockable {
    static func mockRandom() -> Self {
        let all: [URLRequestBuilder.QueryItem] = [
            .ddsource(source: .mockRandom()),
            .ddtags(tags: .mockRandom()),
        ]
        return all.randomElement()!
    }

    static func mockAny() -> Self {
        return .ddsource(source: .mockRandom(among: .alphanumerics))
    }
}

extension URLRequestBuilder.HTTPHeader: RandomMockable, AnyMockable {
    static func mockRandom() -> Self {
        let all: [URLRequestBuilder.HTTPHeader] = [
            .contentTypeHeader(contentType: Bool.random() ? .applicationJSON : .textPlainUTF8),
            .userAgentHeader(appName: .mockRandom(among: .alphanumerics), appVersion: .mockRandom(among: .alphanumerics), device: .mockAny()),
            .ddAPIKeyHeader(clientToken: .mockRandom(among: .alphanumerics)),
            .ddEVPOriginHeader(source: .mockRandom(among: .alphanumerics)),
            .ddEVPOriginVersionHeader(sdkVersion: .mockRandom(among: .alphanumerics)),
            .ddRequestIDHeader()
        ]
        return all.randomElement()!
    }

    static func mockAny() -> Self {
        return .ddEVPOriginVersionHeader(sdkVersion: "1.2.3")
    }
}

extension URLRequestBuilder: AnyMockable {
    static func mockAny() -> Self {
        return mockWith()
    }

    static func mockWith(
        url: URL = .mockAny(),
        queryItems: [QueryItem] = [],
        headers: [HTTPHeader] = []
    ) -> Self {
        return URLRequestBuilder(
            url: url,
            queryItems: queryItems,
            headers: headers
        )
    }
}

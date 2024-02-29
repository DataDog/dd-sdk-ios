/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct MetricFeature: DatadogRemoteFeature {
    static let name = "metrics"

    let requestBuilder: DatadogInternal.FeatureRequestBuilder
    let messageReceiver: DatadogInternal.FeatureMessageReceiver = NOPFeatureMessageReceiver()
    let subscriber: DatadogMetricSubscriber

    init(
        apiKey: String,
        subscriber: DatadogMetricSubscriber,
        customIntakeURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.init(
            requestBuilder: RequestBuilder(
                apiKey: apiKey,
                customIntakeURL: customIntakeURL,
                telemetry: telemetry
            ),
            subscriber: subscriber
        )
    }

    init(
        requestBuilder: FeatureRequestBuilder,
        subscriber: DatadogMetricSubscriber
    ) {
        self.requestBuilder = requestBuilder
        self.subscriber = subscriber
    }
}

/// The Logging URL Request Builder for formatting and configuring the `URLRequest`
/// to upload logs data.
internal struct RequestBuilder: FeatureRequestBuilder {
    /// Either the API key or a regular client token
    /// For metrics reporting API key is needed
    let apiKey: String
    /// A custom logs intake.
    let customIntakeURL: URL?
    /// Telemetry interface.
    let telemetry: Telemetry

    let format = DataFormat(prefix: #"{ "series": ["#, suffix: "] }", separator: ",")
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(
        apiKey: String,
        customIntakeURL: URL? = nil,
        telemetry: Telemetry = NOPTelemetry()
    ) {
        self.apiKey = apiKey
        self.customIntakeURL = customIntakeURL
        self.telemetry = telemetry
    }

    func request(for events: [Event], with context: DatadogContext) throws -> URLRequest {
        let submissions = try events.map(\.data).map { try decoder.decode(Submission.self, from: $0) }

        let aggregators: [Submission.Metadata: Aggregator] = submissions.reduce(into: [:]) { aggregators, submission in
            var aggregator = aggregators[submission.metadata] ?? {
                switch submission.metadata.type {
                case .count: return CountAggregator()
                case .gauge: return GaugeAggregator()
                case .histogram: return HistogramAggregator()
                }
            }()

            aggregator.add(submission)
            aggregators[submission.metadata] = aggregator
        }

        let data = try aggregators.values
            .map { $0.flush() }
            .reduce([], +)
            .map { try encoder.encode($0) }

        let builder = URLRequestBuilder(
            url: url(with: context),
            queryItems: [
                .ddsource(source: context.source)
            ],
            headers: [
                .contentTypeHeader(contentType: .applicationJSON),
                .userAgentHeader(
                    appName: context.applicationName,
                    appVersion: context.version,
                    device: context.device
                ),
                .ddAPIKeyHeader(clientToken: apiKey),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader(),
            ],
            telemetry: telemetry
        )

        let body = format.format(data)
        return builder.uploadRequest(with: body)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? {
            switch context.site {
            // swiftlint:disable force_unwrapping
            case .us1: return URL(string: "https://api.datadoghq.com/api/v2/series")!
            case .us3: return URL(string: "https://api.us3.datadoghq.com/api/v2/series")!
            case .us5: return URL(string: "https://api.us5.datadoghq.com/api/v2/series")!
            case .eu1: return URL(string: "https://api.datadoghq.eu/api/v2/series")!
            case .ap1: return URL(string: "https://api.ap1.datadoghq.com/api/v2/series")!
            case .us1_fed: return URL(string: "https://api.ddog-gov.com/api/v2/series")!
            // swiftlint:enable force_unwrapping
            }
        }()
    }
}

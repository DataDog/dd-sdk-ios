/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct EvaluationRequestBuilder: FeatureRequestBuilder {
    let customIntakeURL: URL?
    let telemetry: Telemetry

    func request(for events: [Event], with context: DatadogContext, execution: ExecutionContext) throws -> URLRequest {
        let evaluationEvents: [FlagEvaluationEvent] = try events.map { event in
            guard let evaluation = try? JSONDecoder().decode(FlagEvaluationEvent.self, from: event.data) else {
                throw InternalError(description: "Failed to decode FlagEvaluationEvent from Event data")
            }
            return evaluation
        }

        let batchContext = buildEvaluationContext(from: context)
        let batchedEvaluations = BatchedFlagEvaluations(
            context: batchContext,
            flagEvaluations: evaluationEvents
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let jsonData = try encoder.encode(batchedEvaluations)

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
                    device: context.device,
                    os: context.os
                ),
                .ddAPIKeyHeader(clientToken: context.clientToken),
                .ddEVPOriginHeader(source: context.ciAppOrigin ?? context.source),
                .ddEVPOriginVersionHeader(sdkVersion: context.sdkVersion),
                .ddRequestIDHeader()
            ],
            telemetry: telemetry
        )

        return builder.uploadRequest(with: jsonData, compress: false)
    }

    private func url(with context: DatadogContext) -> URL {
        customIntakeURL ?? context.site.endpoint.appendingPathComponent("api/v2/flagevaluation")
    }

    private func buildEvaluationContext(from context: DatadogContext) -> EvaluationContext {
        return EvaluationContext(
            geo: nil,
            device: EvaluationContext.DeviceInfo(
                name: context.device.name,
                type: context.device.type.normalizedDeviceType,
                brand: context.device.brand,
                model: context.device.model
            ),
            os: EvaluationContext.OSInfo(
                name: context.os.name,
                version: context.os.version
            ),
            service: context.service,
            version: context.version,
            env: context.env,
            rum: nil
        )
    }
}

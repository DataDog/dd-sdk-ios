/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension URLRequest {
    internal static func flagAssignmentsRequest(
        url: URL,
        evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        customHeaders: [String: String]?
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        request.setValue("application/vnd.api+json", forHTTPHeaderField: "Content-Type")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue(context.clientToken, forHTTPHeaderField: "dd-client-token")

        if let applicationId = context.additionalContext(ofType: RUMCoreContext.self)?.applicationID {
            request.setValue(applicationId, forHTTPHeaderField: "dd-application-id")
        }

        if let customHeaders {
            for (key, value) in customHeaders {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let requestBody = FlagAssignmentsRequestBody(
            environment: FlagAssignmentsRequestBody.Environment(
                name: context.env,
                datadogEnvironment: context.env
            ),
            subject: FlagAssignmentsRequestBody.Subject(
                targetingKey: evaluationContext.targetingKey,
                targetingAttributes: evaluationContext.attributes
            )
        )

        let encoder = JSONEncoder.dd.default()
        request.httpBody = try encoder.encode(requestBody)

        return request
    }
}

internal struct FlagAssignmentsRequestBody {
    struct Subject: Encodable {
        private enum CodingKeys: String, CodingKey {
            case targetingKey = "targeting_key"
            case targetingAttributes = "targeting_attributes"
        }

        let targetingKey: String
        let targetingAttributes: [String: AnyValue]
    }

    struct Environment: Encodable {
        private enum CodingKeys: String, CodingKey {
            case name
            case datadogEnvironment = "dd_env"
        }

        let name: String
        let datadogEnvironment: String
    }

    let environment: Environment
    let subject: Subject
}

extension FlagAssignmentsRequestBody: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case attributes
        case flags
        case environment = "env"
        case subject
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)

        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        try dataContainer.encode("precompute-assignments-request", forKey: .type)

        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(environment, forKey: .environment)
        try attributesContainer.encode(subject, forKey: .subject)
    }
}

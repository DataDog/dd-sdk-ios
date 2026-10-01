/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsWrapperSource {
    let sdkName: String
    let sdkVersion: String
    let nativeBridgeVersion: String
}

extension URLRequest {
    internal static func flagAssignmentsRequest(
        url: URL,
        evaluationContext: FlagsEvaluationContext,
        context: DatadogContext,
        customHeaders: [String: String]?,
        wrapperSource: FlagsWrapperSource? = nil
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

        // Older bridges cannot identify the loaded JavaScript reader.
        let wrapper = wrapperSource ?? (context.source == "react-native"
            ? FlagsWrapperSource(sdkName: "dd-sdk-reactnative", sdkVersion: "unknown", nativeBridgeVersion: "unknown")
            : nil)
        let nativeSDK = FlagAssignmentsRequestBody.SDK(
            sdkName: FlagsSDKMetadata.name,
            sdkVersion: FlagsSDKMetadata.version
        )
        let requestBody = FlagAssignmentsRequestBody(
            environment: FlagAssignmentsRequestBody.Environment(
                name: context.env,
                datadogEnvironment: context.env
            ),
            source: FlagAssignmentsRequestBody.Source(
                sdkName: wrapper?.sdkName ?? nativeSDK.sdkName,
                sdkVersion: wrapper?.sdkVersion ?? nativeSDK.sdkVersion,
                nativeBridgeVersion: wrapper?.nativeBridgeVersion,
                nativeSDK: wrapper == nil ? nil : nativeSDK
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

    struct SDK: Encodable {
        private enum CodingKeys: String, CodingKey {
            case sdkName = "sdk_name"
            case sdkVersion = "sdk_version"
        }

        let sdkName: String
        let sdkVersion: String
    }

    struct Source: Encodable {
        private enum CodingKeys: String, CodingKey {
            case sdkName = "sdk_name"
            case sdkVersion = "sdk_version"
            case nativeBridgeVersion = "native_bridge_version"
            case nativeSDK = "native_sdk"
        }

        let sdkName: String
        let sdkVersion: String
        let nativeBridgeVersion: String?
        let nativeSDK: SDK?
    }

    let environment: Environment
    let source: Source
    let subject: Subject
}

extension FlagAssignmentsRequestBody: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case attributes
        case flags
        case environment = "env"
        case source
        case subject
    }

    func encode(to encoder: any Encoder) throws {
        var rootContainer = encoder.container(keyedBy: CodingKeys.self)

        var dataContainer = rootContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .data)
        try dataContainer.encode("precompute-assignments-request", forKey: .type)

        var attributesContainer = dataContainer.nestedContainer(keyedBy: CodingKeys.self, forKey: .attributes)
        try attributesContainer.encode(environment, forKey: .environment)
        try attributesContainer.encode(source, forKey: .source)
        try attributesContainer.encode(subject, forKey: .subject)
    }
}

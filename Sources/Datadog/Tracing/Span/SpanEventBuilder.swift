/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builds `SpanEvent` representation (for later serialization) from span information recorded in `DDSpan` and values received from global configuration.
internal struct SpanEventBuilder {
    /// Service name to encode in span.
    let serviceName: String?
    /// Enriches traces with network connection info.
    /// This means: reachability status, connection type, mobile carrier name and many more will be added to every span and span logs.
    /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
    let sendNetworkInfo: Bool
    /// Span events mapper configured by the user, `nil` if not set.
    let eventsMapper: SpanEventMapper?

    func createSpanEvent(
        context: DatadogContext,
        traceID: TracingUUID,
        spanID: TracingUUID,
        parentSpanID: TracingUUID?,
        operationName: String,
        startTime: Date,
        finishTime: Date,
        tags: [String: Encodable],
        baggageItems: [String: String],
        logFields: [[String: Encodable]]
    ) -> SpanEvent {
        let tagsReducer = SpanTagsReducer(spanTags: tags, logFields: logFields)

        var tags: [String: String]

        // Add baggage items as tags
        tags = baggageItems

        // Add regular tags (prefer regular tags over baggate items)
        let regularTags = castValuesToString(tagsReducer.reducedSpanTags)
        tags.merge(regularTags) { _, regularTag in regularTag }

        // Transform user info to `SpanEvent.UserInfo` representation
        let spanUserInfo = SpanEvent.UserInfo(
            id: context.userInfo?.id,
            name: context.userInfo?.name,
            email: context.userInfo?.email,
            extraInfo: context.userInfo.map { castValuesToString($0.extraInfo) } ?? [:]
        )

        let span = SpanEvent(
            traceID: traceID,
            spanID: spanID,
            parentID: parentSpanID,
            operationName: operationName,
            serviceName: serviceName ?? context.service,
            resource: tagsReducer.extractedResourceName ?? operationName,
            startTime: startTime.addingTimeInterval(context.serverTimeOffset),
            duration: finishTime.timeIntervalSince(startTime),
            isError: tagsReducer.extractedIsError ?? false,
            source: context.source,
            origin: context.ciAppOrigin,
            tracerVersion: context.sdkVersion,
            applicationVersion: context.version,
            networkConnectionInfo: sendNetworkInfo ? context.networkConnectionInfo : nil,
            mobileCarrierInfo: sendNetworkInfo ? context.carrierInfo : nil,
            userInfo: spanUserInfo,
            tags: tags
        )

        if let eventMapper = eventsMapper {
            return eventMapper(span)
        } else {
            return span
        }
    }

    // MARK: - Attributes Conversion

    /// Encodes `Span` attributes to JSON strings
    private let attributesJSONEncoder: JSONEncoder = .default()

    /// Converts `Encodable` attributes to its lossless JSON string representation, e.g.:
    /// * it will convert `"abc"` string value to `"abc"` JSON string value
    /// * it will convert `1` integer value to `"1"` JSON string value
    /// * it will convert `true` boolean value to `"true"` JSON string value
    /// * it will convert `Person(name: "foo")` encodable struct to `"{\"name\": \"foo\"}"` JSON string value
    private func castValuesToString(_ dictionary: [String: Encodable]) -> [String: String] {
        var casted: [String: String] = [:]

        dictionary.forEach { key, value in
            if let stringValue = value as? String {
                casted[key] = stringValue
            } else if let urlValue = value as? URL {
                casted[key] = urlValue.absoluteString
            } else {
                do {
                    let encodable = AnyEncodable(value)
                    let jsonData: Data

                    if #available(iOS 13.0, *) {
                        jsonData = try attributesJSONEncoder.encode(encodable)
                    } else {
                        // Prior to `iOS13.0` the `JSONEncoder` is unable to encode primitive values - it expects them to be
                        // wrapped inside top-level JSON object (array or dictionary). Reference: https://bugs.swift.org/browse/SR-6163
                        //
                        // As a workaround, we serialize the `encodable` as a JSON array and then remove `[` and `]` bytes from serialized data.
                        let temporaryJsonArrayData = try attributesJSONEncoder.encode([encodable])

                        let subdataStartIndex = temporaryJsonArrayData.startIndex.advanced(by: 1)
                        let subdataEndIndex = temporaryJsonArrayData.endIndex.advanced(by: -1)

                        guard subdataStartIndex < subdataEndIndex else {
                            // This error should never be thrown, as the `temporaryJsonArrayData` will always contain at
                            // least two bytes standing for `[` and `]`. This check is just for sanity.
                            let encodingContext = EncodingError.Context(
                                codingPath: [],
                                debugDescription: "Failed to use temporary array container when encoding span tag '\(key)' to JSON string."
                            )
                            DD.telemetry.error(encodingContext.debugDescription)
                            throw EncodingError.invalidValue(encodable.value, encodingContext)
                        }

                        jsonData = temporaryJsonArrayData.subdata(in: subdataStartIndex..<subdataEndIndex)
                    }

                    if let stringValue = String(data: jsonData, encoding: .utf8) {
                        casted[key] = stringValue
                    } else {
                        let encodingContext = EncodingError.Context(
                            codingPath: [],
                            debugDescription: "Failed to read utf-8 JSON data when encoding span tag '\(key)' to JSON string."
                        )
                        DD.telemetry.error(encodingContext.debugDescription)
                        throw EncodingError.invalidValue(encodable.value, encodingContext)
                    }
                } catch let error {
                    DD.logger.error(
                        """
                        Failed to convert span `Encodable` attribute to `String`. The value of `\(key)` will not be sent.
                        """,
                        error: error
                    )
                }
            }
        }

        return casted
    }
}

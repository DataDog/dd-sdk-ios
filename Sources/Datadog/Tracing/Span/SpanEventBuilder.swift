/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `SpanEvent` representation (for later serialization) from span information recorded in `DDSpan` and values received from global configuration.
internal struct SpanEventBuilder {
    /// SDK version to encode in the span.
    let sdkVersion: String
    /// Application version to encode in span.
    let applicationVersion: String
    /// Service name to encode in span.
    let serviceName: String
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider
    /// Shared network connection info provider (or `nil` if disabled for given tracer).
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType?
    /// Shared mobile carrier info provider (or `nil` if disabled for given tracer).
    let carrierInfoProvider: CarrierInfoProviderType?
    /// Adjusts span's time (device time) to server time.
    let dateCorrector: DateCorrector
    /// Source tag to encode in span (e.g. `ios` for native iOS).
    let source: String
    /// Optional Origin tag to encode in span (e.g. `ciapp-test`).
    let origin: String?
    /// Span events mapper configured by the user, `nil` if not set.
    let eventsMapper: SpanEventMapper?

    func createSpanEvent(
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
        let userInfo = userInfoProvider.value
        let spanUserInfo = SpanEvent.UserInfo(
            id: userInfo.id,
            name: userInfo.name,
            email: userInfo.email,
            extraInfo: castValuesToString(userInfo.extraInfo)
        )

        let span = SpanEvent(
            traceID: traceID,
            spanID: spanID,
            parentID: parentSpanID,
            operationName: operationName,
            serviceName: serviceName,
            resource: tagsReducer.extractedResourceName ?? operationName,
            startTime: startTime.addingTimeInterval(dateCorrector.offset),
            duration: finishTime.timeIntervalSince(startTime),
            isError: tagsReducer.extractedIsError ?? false,
            source: source,
            origin: origin,
            tracerVersion: sdkVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfoProvider?.current,
            mobileCarrierInfo: carrierInfoProvider?.current,
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
                    let encodable = CodableValue(value)
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

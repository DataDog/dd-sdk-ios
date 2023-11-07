/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

internal struct ResourcesRequestBuilder: FeatureRequestBuilder {
    /// Custom URL for uploading data to.
    let customUploadURL: URL?
    /// Sends telemetry through sdk core.
    let telemetry: Telemetry
    /// Builds multipart form for request's body.
    var multipartBuilder: MultipartFormDataBuilder = MultipartFormData(boundary: UUID())
    
    func request(for events: [Event], with context: DatadogContext) throws -> URLRequest {
        return URLRequest(url: URL(string: "https://datadoghq.com")!)
    }
}
#endif

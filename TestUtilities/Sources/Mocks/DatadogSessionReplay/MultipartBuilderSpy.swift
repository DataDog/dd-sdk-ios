/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@testable import DatadogSessionReplay

class MultipartBuilderSpy: MultipartFormDataBuilder {
    var formFields: [String: String] = [:]
    var formFiles: [(filename: String, data: Data, mimeType: String)] = []
    var returnedData: Data = .mockRandom()

    let boundary: String = UUID().uuidString

    func addFormField(name: String, value: String) { formFields[name] = value }

    func addFormData(name: String, filename: String, data: Data, mimeType: String) {
        formFiles.append((filename: filename, data: data, mimeType: mimeType))
    }

    func build() -> Data { returnedData }
}
#endif

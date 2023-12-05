/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay

struct MockImageDataProvider: ImageDataProviding {
    var contentBase64String: String
    var identifier: String

    func contentBase64String(of image: UIImage?) -> DatadogSessionReplay.ImageResource? {
        return .init(identifier: identifier, base64: contentBase64String)
    }

    func contentBase64String(of image: UIImage?, tintColor: UIColor?) -> DatadogSessionReplay.ImageResource? {
        return .init(identifier: identifier, base64: contentBase64String)
    }

    init(
        contentBase64String: String = "mock_base64_string",
        identifier: String = "mock_identifier"
    ) {
        self.contentBase64String = contentBase64String
        self.identifier = identifier
    }
}

internal func mockRandomImageDataProvider() -> ImageDataProviding {
    return MockImageDataProvider(contentBase64String: .mockRandom())
}

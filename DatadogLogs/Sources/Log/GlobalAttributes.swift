/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class GlobalAttributes: Sendable {
    private let attributes: ReadWriteLock<[String: Encodable]>

    init(attributes: [String : Encodable]) {
        self.attributes = .init(wrappedValue: attributes)
    }

    func addAttribute(key: AttributeKey, value: AttributeValue) {
        attributes.mutate { $0[key] = value }
    }

    func removeAttribute(forKey key: AttributeKey) {
        attributes.mutate { $0.removeValue(forKey: key) }
    }

    func getAttributes() -> [String: Encodable] {
        return attributes.wrappedValue
    }
}

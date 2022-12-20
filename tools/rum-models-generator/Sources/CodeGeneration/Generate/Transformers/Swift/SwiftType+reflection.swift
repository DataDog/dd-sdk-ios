/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

// MARK: - Reflection Helpers

internal protocol SwiftReflectable {
    func conforms(to swiftProtocol: SwiftProtocol) -> Bool
}

extension SwiftProtocol: SwiftReflectable {
    func conforms(to swiftProtocol: SwiftProtocol) -> Bool {
        return self == swiftProtocol
            || conformance.contains { $0.conforms(to: swiftProtocol) }
    }
}

extension SwiftStruct: SwiftReflectable {
    func conforms(to swiftProtocol: SwiftProtocol) -> Bool {
        return conformance.contains { $0.conforms(to: swiftProtocol) }
    }
}

extension SwiftEnum: SwiftReflectable {
    func conforms(to swiftProtocol: SwiftProtocol) -> Bool {
        return conformance.contains { $0.conforms(to: swiftProtocol) }
    }
}

extension SwiftAssociatedTypeEnum: SwiftReflectable {
    func conforms(to swiftProtocol: SwiftProtocol) -> Bool {
        return conformance.contains { $0.conforms(to: swiftProtocol) }
    }
}

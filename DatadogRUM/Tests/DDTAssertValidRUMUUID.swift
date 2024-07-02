/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import TestUtilities

func DDTAssertValidRUMUUID(_ uuid: @autoclosure () throws -> String?, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    _DDEvaluateAssertion(message: message(), file: file, line: line) {
        try _DDTAssertValidRUMUUID(uuid())
    }
}

private func _DDTAssertValidRUMUUID(_ uuid: String?) throws {
    let schemaReference = "given by https://github.com/DataDog/rum-events-format/blob/master/schemas/_common-schema.json"
    guard let uuid = uuid else {
        throw DDAssertError.expectedFailure("`nil` is not valid RUM UUID \(schemaReference)")
    }

    let regex = #"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#

    if uuid.range(of: regex, options: .regularExpression, range: nil, locale: nil) == nil {
        throw DDAssertError.expectedFailure("\(uuid) is not valid RUM UUID - it doesn't match \(regex) \(schemaReference)")
    }
}

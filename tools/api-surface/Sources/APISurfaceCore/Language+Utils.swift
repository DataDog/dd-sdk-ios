/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import ArgumentParser
import Foundation
import SourceKittenFramework

extension Language: @retroactive RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue.lowercased() {
        case Language.swift.rawValue:
            self = .swift
        case Language.objc.rawValue:
            self = .objc
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .swift:
            "swift"
        case .objc:
            "objc"
        }
    }
}

extension Language: @retroactive Decodable {}

extension Language: @retroactive ExpressibleByArgument {}

extension Language {
    func shouldParse(path: String) -> Bool {
        let fileName = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
        let isObjcSuffixed = fileName.hasSuffix(Language.objc.rawValue)

        switch self {
        case .swift:
            return isObjcSuffixed == false
        case .objc:
            return isObjcSuffixed
        }
    }
}

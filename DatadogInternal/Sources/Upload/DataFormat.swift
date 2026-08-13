/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describes the format of writing and reading data from files.
public struct DataFormat {
    /// Prefixes the batch payload read from file.
    private let prefixData: Data
    /// Suffixes the batch payload read from file.
    private let suffixData: Data
    /// Separates entities written to file.
    private let separatorByte: UInt8

    // MARK: - Initialization

    public init(
        prefix: String,
        suffix: String,
        separator: Character
    ) {
        self.prefixData = prefix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.suffixData = suffix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.separatorByte = separator.asciiValue!   // swiftlint:disable:this force_unwrapping
    }

    /// Formats the given data sequence by applying the prefix, separator,
    /// and suffix.
    ///
    /// - Parameter data: The data sequence.
    /// - Returns: the formatted data.
    public func format(_ data: [Data]) -> Data {
        // Append to a single buffer to avoid copying the entire payload for every event.
        var formattedData = Data()
        formattedData.append(prefixData)

        for (index, event) in data.enumerated() {
            if index > 0 {
                formattedData.append(separatorByte)
            }
            formattedData.append(event)
        }

        formattedData.append(suffixData)
        return formattedData
    }
}

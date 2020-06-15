/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes the format of writing and reading data from files.
internal struct DataFormat {
    /// Prefixes the batch payload read from file.
    let prefixData: Data
    /// Suffixes the batch payload read from file.
    let suffixData: Data
    /// Separates entities written to file.
    let separatorData: Data

    // MARK: - Initialization

    init(
        prefix: String,
        suffix: String,
        separator: String
    ) {
        self.prefixData = prefix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.suffixData = suffix.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
        self.separatorData = separator.data(using: .utf8)! // swiftlint:disable:this force_unwrapping
    }
}

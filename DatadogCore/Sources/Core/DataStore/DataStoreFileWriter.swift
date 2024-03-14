/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal enum DataStoreFileWritingError: Error {
    case failedToEncodeVersion(Error)
    case failedToEncodeData(Error)
}

internal struct DataStoreFileWriter {
    internal enum Constants {
        /// The maximum length of data (Value) in TLV block defining key data.
        static let maxDataLength = 10.MB.asUInt64() // 10MB
    }

    let file: File

    func write(data: Data, version: DataStoreKeyVersion) throws {
        let versionBlock = DataStoreBlock(type: .version, data: self.data(from: version))
        let dataBlock = DataStoreBlock(type: .data, data: data)

        var encoded = Data()
        do {
            try encoded.append(versionBlock.serialize(maxLength: UInt64(MemoryLayout<DataStoreKeyVersion>.size)))
        } catch let error {
            throw DataStoreFileWritingError.failedToEncodeVersion(error)
        }
        do {
            try encoded.append(dataBlock.serialize(maxLength: Constants.maxDataLength))
        } catch let error {
            throw DataStoreFileWritingError.failedToEncodeData(error)
        }
        try file.write(data: encoded) // atomic write
    }

    // MARK: - Encoding

    private func data<T: FixedWidthInteger>(from value: T) -> Data {
        return withUnsafeBytes(of: value) { Data($0) }
    }
}

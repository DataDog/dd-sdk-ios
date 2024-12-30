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
    let file: File

    func write(data: Data, version: DataStoreKeyVersion) throws {
        let versionBlock = DataStoreBlock(type: .version, data: self.data(from: version))
        let dataBlock = DataStoreBlock(type: .data, data: data)

        var encoded = Data()
        do {
            try encoded.append(versionBlock.serialize(maxLength: TLVBlockSize(MemoryLayout<DataStoreKeyVersion>.size)))
        } catch let error {
            throw DataStoreFileWritingError.failedToEncodeVersion(error)
        }
        do {
            try encoded.append(dataBlock.serialize(maxLength: MAX_DATA_LENGTH))
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

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Interface that allows storing data in encrypted format. Encryption/decryption round should
/// return exactly the same data as it given for the encryption originally (even if decryption
/// happens in another process/app launch).
public protocol DataEncryption {
    /// Encrypts given `Data` with user-chosen encryption.
    ///
    /// - Parameter data: Data to encrypt.
    /// - Returns: The encrypted data.
    func encrypt(data: Data) throws -> Data

    /// Decrypts given `Data` with user-chosen encryption.
    ///
    /// Beware that data to decrypt could be encrypted in a previous app launch, so
    /// implementation should be aware of the case when decryption could fail (for example,
    /// key used for encryption is different from key used for decryption, if they are unique
    /// for every app launch).
    ///
    /// - Parameter data: Data to decrypt.
    /// - Returns: The decrypted data.
    func decrypt(data: Data) throws -> Data
}

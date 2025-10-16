/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error that can occur during Flags SDK operations.
public enum FlagsError: Error {
    /// A network error occurred while communicating with the flags service.
    ///
    /// The associated value contains the underlying network error.
    ///
    /// - Parameter Error: The underlying network error that occurred.
    case networkError(Error)

    /// The flags service returned an invalid or unexpected response.
    ///
    /// This may indicate a service error or an incompatible API version.
    case invalidResponse

    /// The flags client was not properly initialized.
    ///
    /// This error occurs when attempting to use a client that has been deallocated
    /// or hasn't completed initialization.
    case clientNotInitialized

    /// The flags configuration is invalid.
    ///
    /// This may occur if required configuration parameters are missing or malformed.
    case invalidConfiguration
}

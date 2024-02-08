/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension URLSessionTask: DatadogExtended {}
extension DatadogExtension where ExtendedType: URLSessionTask {
    /// Overrides the current request of the ``URLSessionTask``.
    ///
    /// The current request must be overriden before the task resumes.
    ///
    /// - Parameter request: The new request.
    func override(currentRequest request: URLRequest) {
        // The `URLSessionTask` is Key-Value Coding compliant and we can
        // set the `currentRequest` property
        type.setValue(request, forKey: "currentRequest")
    }

    /// Returns the delegate instance the task is reporting to.
    var delegate: URLSessionDelegate? {
        if #available(iOS 15.0, tvOS 15.0, *), let delegate = type.delegate {
            return delegate
        }

        // The `URLSessionTask` is Key-Value Coding compliant and retains a
        // `session` property
        guard let session = type.value(forKey: "session") as? URLSession else {
            return nil
        }

        return session.delegate
    }
}

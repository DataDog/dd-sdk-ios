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

    /// Infers if the ``URLSessionTask`` will invoked selectors from the given delegate type.
    ///
    /// - Parameter klass: The expected delegate type.
    /// - Returns: Returns `true` if the task will invoked selectors from the delegate type.
    func isDelegatingTo(klass: URLSessionDelegate.Type) -> Bool {
        if #available(iOS 15.0, tvOS 15.0, *), type.delegate?.isKind(of: klass) == true {
            return true
        }

        // The `URLSessionTask` is Key-Value Coding compliant and retains a
        // `session` property
        guard let session = type.value(forKey: "session") as? URLSession else {
            return false
        }

        return session.delegate?.isKind(of: klass) == true
    }

    /// Infers if the ``URLSessionTask`` will invoked selectors from the given delegate protocol.
    ///
    /// - Parameter protocol: The expected delegate protocol.
    /// - Returns: Returns `true` if the task will invoked selectors from the delegate type.
    func isDelegatingTo(protocol: Protocol) -> Bool {
        if #available(iOS 15.0, tvOS 15.0, *), type.delegate?.conforms(to: `protocol`) == true {
            return true
        }

        // The `URLSessionTask` is Key-Value Coding compliant and retains a
        // `session` property
        guard let session = type.value(forKey: "session") as? URLSession else {
            return false
        }

        return session.delegate?.conforms(to: `protocol`) == true
    }
}

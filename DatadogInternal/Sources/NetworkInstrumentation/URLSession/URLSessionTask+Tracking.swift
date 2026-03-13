/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import AVFoundation
import Foundation

extension URLSessionTask: DatadogExtended {}
extension DatadogExtension where ExtendedType: URLSessionTask {
    /// Overrides the current request of the ``URLSessionTask``.
    ///
    /// The current request must be overridden before the task resumes.
    ///
    /// - Parameter request: The new request.
    func override(currentRequest request: URLRequest) {
        // The `URLSessionTask` is Key-Value Coding compliant and we can
        // set the `currentRequest` property
        type.setValue(request, forKey: "currentRequest")
    }

    /// Returns the delegate instance the task is reporting to.
    var delegate: URLSessionDelegate? {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, *), let delegate = type.delegate {
            return delegate
        }

        // The `URLSessionTask` is Key-Value Coding compliant and retains a
        // `session` property
        guard let session = type.value(forKey: "session") as? URLSession else {
            return nil
        }

        return session.delegate
    }

    var hasCompletion: Bool {
        get {
            let value = objc_getAssociatedObject(type, &hasCompletionKey) as? Bool
            return value == true
        }
        set {
            if newValue {
                objc_setAssociatedObject(type, &hasCompletionKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                objc_setAssociatedObject(type, &hasCompletionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
}

private var hasCompletionKey: Void?

extension URLSessionTask {
    /// Returns `true` if the task supports standard `URLSessionTask` property access and
    /// can be instrumented. Some subclasses declare properties like `currentRequest` and
    /// `response` as `NS_UNAVAILABLE` and throw `NSGenericException` at runtime when accessed.
    ///
    /// Known unsupported types:
    /// - `AVAssetDownloadTask` (ObjC: `NSURLSessionAVAssetDownloadTask`)
    /// - `AVAggregateAssetDownloadTask` (ObjC: `NSURLSessionAVAggregateAssetDownloadTask`)
    ///
    /// The `is` check covers both the public Swift type and its private ObjC-bridged name,
    /// as well as any private concrete subclasses (e.g. `__NSCFBackgroundAVAssetDownloadTask`).
    var isSupportedForInstrumentation: Bool {
        !(self is AVAssetDownloadTask || self is AVAggregateAssetDownloadTask)
    }
}

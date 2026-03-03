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

    #if os(watchOS)
    /// Indicates whether this task is an internal OS-created task wrapper.
    ///
    /// On watchOS, a single user-created task can result in multiple internal `URLSessionTask` wrapper
    /// objects all sharing the same `taskIdentifier`. The user-facing task has no internal delegate
    /// wrapper, while OS-internal tasks (e.g. the actual connection task, Privacy Dashboard shadow task)
    /// have `_internalDelegateWrapper` set to route their callbacks internally.
    ///
    /// We use this to skip instrumentation of internal OS task wrappers — only the user-facing task
    /// (with no internal delegate wrapper) should be instrumented.
    ///
    /// - Note (hypothesis by @maxep): This may be specific to watchOS because of its companion link
    ///   architecture. Watch apps likely proxy networking through the paired iPhone or via the Watch's
    ///   own radio with Privacy Proxy involvement, which could require the OS to spawn multiple internal
    ///   task wrappers per user request. On iOS/tvOS/macOS, tasks connect directly to the network stack
    ///   without such indirection, so only one task object is created per request.
    var isInternalTask: Bool {
        // `_internalDelegateWrapper` is a private ivar on `NSURLSessionTask`. It is non-nil on
        // OS-internal task wrappers created by watchOS to handle the actual networking, and nil
        // on user-created tasks returned from `URLSession.dataTask(...)`.
        type.value(forKey: "_internalDelegateWrapper") != nil
    }
    #endif

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
    /// `URLSessionTask` subclasses that declare most of their inherited properties as `NS_UNAVAILABLE`
    /// and throw `NSGenericException` at runtime when those properties are accessed.
    /// Resolved once using `NSClassFromString` to avoid importing AVFoundation.
    private static let unsupportedTaskClasses: [AnyClass] = {
        [
            "AVAssetDownloadTask",
            "NSURLSessionAVAssetDownloadTask",
            "AVAggregateAssetDownloadTask",
            "NSURLSessionAVAggregateAssetDownloadTask"
        ]
            .compactMap { NSClassFromString($0) }
    }()

    /// Returns `true` if the task supports standard `URLSessionTask` property access and
    /// can be instrumented. Some subclasses declare properties like `currentRequest` and
    /// `response` as `NS_UNAVAILABLE` and throw `NSGenericException` at runtime when accessed.
    var isSupportedForInstrumentation: Bool {
        !Self.unsupportedTaskClasses.contains { self.isKind(of: $0) }
    }
}

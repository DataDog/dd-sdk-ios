/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import _Datadog_Private

internal final class URLSessionSwizzler {
    internal typealias RequestInterceptorIMP = @convention(block) (AnyObject, URLRequest) -> URLRequest?
    internal typealias TaskObserverIMP = @convention(block) (AnyObject, URLSessionTask) -> Void

    private static let queue = DispatchQueue(
        label: "com.datadog.URLSessionSwizzlerQueue",
        target: DispatchQueue.global(qos: .userInteractive)
    )
    private static let templateClass: AnyClass = TemplateURLSession.self
    private static let dynamicClassPrefix: String = "__Datadog"

    static func swizzle(
        _ session: URLSession,
        requestInterceptor: @escaping RequestInterceptorIMP,
        taskObserver: @escaping TaskObserverIMP,
        enforceNewClassConfiguration: Bool = false
    ) throws {
        try queue.sync {
            try? unswizzle(session)
            guard let sessionClass = object_getClass(session) else {
                throw SwizzlerError.objectDoesNotHaveAClass()
            }

            var isNewClassConfigured = false
            let dynamicClass: AnyClass? = Swizzler.dynamicClass(
                with: Self.dynamicClassPrefix,
                superclass: sessionClass
            ) { newClass in
                do {
                    try Swizzler.addMethods(of: Self.templateClass, to: newClass)

                    let interceptorSelector = #selector(TemplateURLSession.injected_interceptRequest(_:))
                    try Swizzler.setBlock(
                        requestInterceptor,
                        implementationOf: interceptorSelector,
                        in: newClass
                    )

                    let observerSelector = #selector(TemplateURLSession.injected_observe(_:))
                    try Swizzler.setBlock(
                        taskObserver,
                        implementationOf: observerSelector,
                        in: newClass
                    )

                    isNewClassConfigured = true
                    return true
                } catch {
                    // TODO: RUMM-300 report error
                    return false
                }
            }
            if enforceNewClassConfiguration && !isNewClassConfigured {
                throw SwizzlerError.dynamicClassAlreadyExists(
                    with: Self.dynamicClassPrefix,
                    basedOn: NSStringFromClass(sessionClass)
                )
            }
            if let registeredDynamicClass = dynamicClass {
                try Swizzler.swizzle(session, with: registeredDynamicClass)
            }
        }
    }

    static func unswizzle(_ session: URLSession, disposeDynamicClass: Bool = false) throws {
        try Swizzler.unswizzle(
            session,
            ifPrefixed: Self.dynamicClassPrefix,
            andDisposeDynamicClass: disposeDynamicClass
        )
    }
}

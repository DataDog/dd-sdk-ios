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

    private static let templateClass: AnyClass = TemplateURLSession.self
    private static let dynamicClassPrefix: String = "__Datadog"

    static func swizzle(
        _ session: URLSession,
        requestInterceptor: @escaping RequestInterceptorIMP,
        taskObserver: @escaping TaskObserverIMP
    ) throws {
        try? unswizzle(session)
        guard let sessionClass = object_getClass(session) else {
            throw SwizzlerError.objectDoesNotHaveAClass()
        }

        let dynamicClass: AnyClass? = Swizzler.createClass(
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

                return true
            } catch {
                // TODO: RUMM-300 report error
                return false
            }
        }
        if let registeredDynamicClass = dynamicClass {
            try Swizzler.swizzle(session, with: registeredDynamicClass)
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

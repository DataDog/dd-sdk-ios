/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import _Datadog_Private

extension Datadog {
    internal typealias RequestInterceptor = (URLRequest) -> URLRequest
    internal typealias TaskObserver = (URLSessionTask) -> Void

    static func trace(_ session: URLSession) throws {
        let requestInterceptor: RequestInterceptor = { originalRequest in
            // TODO: RUMM-300 Set tracer HTTP header values
            return originalRequest
        }
        let taskObserver: TaskObserver = { task in
            // TODO: RUMM-300 observe task to call start/stopSpan
            /*
            Pseudo-code:
            let observation = task.observe(\.state) { observedTask,_ in
                if detectStartEvent() {
                    startSpan()
                } else if detectStopEvent() {
                    stopSpan()
                }
            }
            objc_setAssociatedObject(
                task,
                "__dd_stateObservation",
                observation,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
             */
        }

        try Swizzler.swizzle(
            session,
            requestInterceptor: requestInterceptor,
            taskObserver: taskObserver,
            enforceDynamicClassCreation: false
        )
    }
}

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// `URLSession` Auto Instrumentation feature.
internal class URLSessionAutoInstrumentation {
    static var instance: URLSessionAutoInstrumentation?

    let swizzler: URLSessionSwizzler
    let interceptor: URLSessionInterceptor

    init?(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        dateProvider: DateProvider
    ) {
        do {
            self.interceptor = URLSessionInterceptor(configuration: configuration, dateProvider: dateProvider)
            self.swizzler = try URLSessionSwizzler(interceptor: interceptor)
        } catch {
            consolePrint(
                "🔥 Datadog SDK error: automatic tracking of `URLSession` requests can't be set up due to error: \(error)"
            )
            return nil
        }
    }

    func enable() {
        swizzler.swizzle()
    }

    func subscribe(commandSubscriber: RUMCommandSubscriber) {
        interceptor.rumResourceHandler?.subscribe(commandsSubscriber: commandSubscriber)
    }
}

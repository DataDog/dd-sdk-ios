/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Current `RUMContext` provider.
internal class RUMCurrentContext: RUMContextProvider {
    private let applicationScope: RUMApplicationScope
    /// Queue used to compute the context.
    private let queue: DispatchQueue

    init(applicationScope: RUMApplicationScope, queue: DispatchQueue) {
        self.applicationScope = applicationScope
        self.queue = queue
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        queue.sync {
            activeViewContext ?? sessionContext ?? applicationContext
        }
    }

    // MARK: - Internal

    func async(execute work: @escaping (RUMContext) -> Void) {
        queue.async {
            work(self.activeViewContext ?? self.sessionContext ?? self.applicationContext)
        }
    }

    // MARK: - Private

    private var applicationContext: RUMContext {
        applicationScope.context
    }

    private var sessionContext: RUMContext? {
        applicationScope.sessionScope?.context
    }

    private var activeViewContext: RUMContext? {
        applicationScope.sessionScope?.viewScopes.last?.context
    }
}

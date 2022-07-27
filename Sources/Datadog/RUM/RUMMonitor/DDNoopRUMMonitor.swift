/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// The no-op variant of `DDRUMMonitor`.
internal class DDNoopRUMMonitor: DDRUMMonitor {
    private func warn() {
        DD.logger.critical(
            """
            The `Global.rum` was called but no `RUMMonitor` is registered. Configure and register the RUM Monitor globally before invoking the feature:
                Global.rum = RUMMonitor.initialize()
            See https://docs.datadoghq.com/real_user_monitoring/ios
            """
        )
    }

    override func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startView(
        key: String,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }
}

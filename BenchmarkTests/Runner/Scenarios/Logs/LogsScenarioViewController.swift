/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogLogs

internal class LogsScenarioViewController: GenericViewController {
    private var logger: LoggerProtocol!

    override func viewDidLoad() {
        super.viewDidLoad()
        logger = Logger.create()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        schedule(operation: { [weak self] in self?.sendLog() }, every: 1)
    }

    private func sendLog() {
        logger.debug("Benchmark debug message", attributes: ["attribute": "value"])
    }
}

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

internal class RUMScenarioViewController: GenericViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        startNextView()
        schedule(operation: { [weak self] in self?.startNextView() }, every: 5)
        schedule(operation: { [weak self] in self?.addResource() }, every: 4)
        schedule(operation: { [weak self] in self?.addAction() }, every: 3)
        schedule(operation: { [weak self] in self?.addError() }, every: 10)
    }

    private var viewIndex = 0
    private var resourceIndex = 0
    private var errorIndex = 0
    private var actionIndex = 0

    private func startNextView() {
        defer { viewIndex += 1 }
        debug(#function)
        RUMMonitor.shared().startView(key: "view-\(viewIndex)", name: "BenchmarkView\(viewIndex)")
    }

    private func addResource() {
        defer { resourceIndex += 1 }
        debug(#function)
        let step = resourceIndex % 2
        let resourceKey = "resource-\(resourceIndex - step)"
        if step == 0 {
            RUMMonitor.shared().startResource(resourceKey: resourceKey, url: URL(string: "https://example.com")!)
        } else {
            RUMMonitor.shared().stopResource(resourceKey: resourceKey, statusCode: 200, kind: .fetch, size: 10)
        }
    }

    private func addError() {
        defer { errorIndex += 1 }
        debug(#function)
        RUMMonitor.shared().addError(message: "error-\(errorIndex)", type: "mock", source: .custom)
    }

    private func addAction() {
        defer { actionIndex += 1 }
        
        RUMMonitor.shared().addAction(type: .custom, name: "action-\(actionIndex)")
    }
}

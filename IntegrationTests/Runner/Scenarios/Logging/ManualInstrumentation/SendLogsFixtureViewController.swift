/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogLogs

internal class SendLogsFixtureViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        // Send logs
        logger?.addTag(withKey: "tag1", value: "tag-value")
        logger?.add(tag: "tag2")

        logger?.addAttribute(forKey: "logger-attribute1", value: "string value")
        logger?.addAttribute(forKey: "logger-attribute2", value: 1_000)
        logger?.addAttribute(forKey: "some-url", value: URL(string: "https://example.com/image.png")!)

        logger?.debug("debug message", attributes: ["attribute": "value"])
        logger?.info("info message", attributes: ["attribute": "value"])
        logger?.notice("notice message", attributes: ["attribute": "value"])
        logger?.warn("warn message", attributes: ["attribute": "value"])
        logger?.error("error message", attributes: ["attribute": "value"])
        logger?.critical("critical message", attributes: ["attribute": "value"])

        Logs.addAttribute(forKey: "global-attribute-1", value: "global value")
        Logs.addAttribute(forKey: "global-attribute-2", value: 1_540)
        Logs.addAttribute(forKey: "attribute", value: 20)

        logger?.notice("notice message with global", attributes: ["attribute": "value"])
    }
}

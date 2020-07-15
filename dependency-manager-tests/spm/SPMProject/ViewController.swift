/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import UIKit
import Datadog

internal class ViewController: UIViewController {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func viewDidLoad() {
        super.viewDidLoad()

        Datadog.initialize(
            appContext: .init(),
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "abc", environment: "tests")
                .build()
        )

        self.logger = Logger.builder
            .sendLogsToDatadog(false)
            .printLogsToConsole(true)
            .build()

        Global.sharedTracer = Tracer.initialize(configuration: .init())

        logger.info("It works")

        // Start span, but never finish it (no upload)
        _ = Global.sharedTracer.startSpan(operationName: "This too")
    }
}

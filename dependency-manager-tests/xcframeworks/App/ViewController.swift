/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import Datadog
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogObjc
import DatadogCrashReporting

internal class ViewController: UIViewController {
    private var logger: LoggerProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func viewDidLoad() {
        super.viewDidLoad()

        Datadog.initialize(
            appContext: .init(),
            trackingConsent: .granted,
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "abc", environment: "tests")
                .build()
        )

        Logs.enable()

        DatadogCrashReporter.initialize()

        self.logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: .short
            )
        )

        // RUM APIs must be visible:
        RUM.enable(with: .init(applicationID: "app-id"))
        RUMMonitor.shared().startView(viewController: self)

        // DDURLSessionDelegate APIs must be visible:
        _ = DDURLSessionDelegate()
        _ = DatadogURLSessionDelegate()
        class CustomDelegate: NSObject, __URLSessionDelegateProviding {
            var ddURLSessionDelegate: DatadogURLSessionDelegate { DatadogURLSessionDelegate() }
        }

        // Trace APIs must be visible:
        Trace.enable()

        logger.info("It works")
        _ = Tracer.shared().startSpan(operationName: "this too")

        addLabel()
    }

    private func addLabel() {
        let label = UILabel()
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(label)

        label.text = "Testing..."
        label.textColor = .white
        label.sizeToFit()
        label.center = view.center
    }
}

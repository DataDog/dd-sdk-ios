/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import UIKit
import Datadog
import DatadogAlamofireExtension
import DatadogCrashReporting
import Alamofire

internal class ViewController: UIViewController {
    private var logger: Logger! // swiftlint:disable:this implicitly_unwrapped_optional

    override func viewDidLoad() {
        super.viewDidLoad()

        Datadog.initialize(
            appContext: .init(),
            trackingConsent: .pending,
            configuration: Datadog.Configuration
                .builderUsing(clientToken: "abc", environment: "tests")
                .enableCrashReporting(using: DDCrashReportingPlugin())
                .build()
        )

        self.logger = Logger.builder
            .sendLogsToDatadog(false)
            .printLogsToConsole(true)
            .build()

        Global.sharedTracer = Tracer.initialize(configuration: .init())

        Global.rum = RUMMonitor.initialize()

        logger.info("It works")
        _ = Global.sharedTracer.startSpan(operationName: "This too")
        Global.rum.startView(viewController: self)

        createInstrumentedAlamofireSession()

        addLabel()
    }

    private func createInstrumentedAlamofireSession() {
        _ = Session(
            interceptor: DDRequestInterceptor(),
            eventMonitors: [DDEventMonitor()]
        )
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

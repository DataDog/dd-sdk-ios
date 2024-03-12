/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import UIKit
import DatadogCore
import DatadogLogs
import DatadogTrace
import DatadogRUM
import DatadogAlamofireExtension
import DatadogCrashReporting
import DatadogSessionReplay  // it should compile for iOS and tvOS, but APIs are only available on iOS
import DatadogObjc
import Alamofire

internal class ViewController: UIViewController {
    private var logger: LoggerProtocol! // swiftlint:disable:this implicitly_unwrapped_optional

    override func viewDidLoad() {
        super.viewDidLoad()

        Datadog.initialize(
            with: Datadog.Configuration(clientToken: "abc", env: "tests"),
            trackingConsent: .granted
        )

        Logs.enable()

        CrashReporting.enable()

        self.logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: .short
            )
        )

        // RUM APIs must be visible:
        RUM.enable(with: .init(applicationID: "app-id"))
        RUMMonitor.shared().startView(viewController: self)

        // Trace APIs must be visible:
        Trace.enable()

        logger.info("It works")

        _ = Tracer.shared().startSpan(operationName: "this too")
        #if os(iOS)
        SessionReplay.enable(with: .init(replaySampleRate: 0))
        #endif

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

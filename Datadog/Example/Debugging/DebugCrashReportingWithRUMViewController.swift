/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogRUM

class DebugCrashReportingWithRUMViewController: UIViewController {
    @IBOutlet weak var rumServiceNameTextField: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        rumServiceNameTextField.text = serviceName
        viewNameTextField.placeholder = viewName
        appHangBacktraceStatusLabel.text = Environment.isAppHangBacktraceEnabled()
            ? "Backtraces: ON — launch with `DD_DISABLE_APP_HANG_BACKTRACES` to turn them off"
            : "Backtraces: OFF — `appHangBacktraceEnabled: false`"
    }

    private func crash() {
        let objc = CrashReportingObjcHelpers()
        objc.throwUncaughtNSException()
    }

    // MARK: - Crash after starting RUM session

    @IBOutlet weak var viewNameTextField: UITextField!

    private var viewName: String {
        viewNameTextField.text!.isEmpty ? "FooViewController" : viewNameTextField.text!
    }

    @IBAction func didTapCrashAfterStartingRUMSession(_ sender: Any) {
        (sender as? UIButton)?.disableFor(seconds: 0.5)

        rumMonitor.startView(key: viewName, name: viewName, attributes: [:])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.crash()
        }
    }

    // MARK: - Crash before starting RUM session

    @IBAction func didTapCrashBeforeStartingRUMSession(_ sender: Any) {
        (sender as? UIButton)?.disableFor(seconds: 0.5)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.crash()
        }
    }

    // MARK: - App Hang

    @IBOutlet weak var appHangBacktraceStatusLabel: UILabel!

    /// Blocks the main thread for longer than the `appHangThreshold` configured in `ExampleAppDelegate`,
    /// so RUM reports an App Hang error. Whether that error carries a stack trace depends on
    /// `CrashReporting.Configuration.appHangBacktraceEnabled`.
    @IBAction func didTapHangMainThread(_ sender: Any) {
        (sender as? UIButton)?.disableFor(seconds: 0.5)

        rumMonitor.startView(key: viewName, name: viewName, attributes: [:])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - OOM Crash

    @IBAction func didTapOOMCrash(_ sender: UIButton) {
        DispatchQueue.main.async {
            let megaByte = 1_024 * 1_024
            let memoryPageSize = NSPageSize()
            let memoryPages = megaByte / memoryPageSize

            while true {
                // Allocate one MB and set one element of each memory page to something.
                let ptr = UnsafeMutablePointer<Int8>.allocate(capacity: megaByte)
                for i in 0..<memoryPages {
                    ptr[i * memoryPageSize] = 40
                }
            }
        }
    }
}

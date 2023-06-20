/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import DatadogLogs
import Datadog

class DebugLoggingViewController: UIViewController {
    @IBOutlet weak var logLevelSegmentedControl: UISegmentedControl!
    @IBOutlet weak var logMessageTextField: UITextField!
    @IBOutlet weak var logServiceNameTextField: UITextField!
    @IBOutlet weak var sendOnceButton: UIButton!
    @IBOutlet weak var send10xButton: UIButton!
    @IBOutlet weak var stressTestButton: UIButton!
    @IBOutlet weak var consoleTextView: UITextView!

    struct StructError: Error {
        let property: String
    }
    enum EnumError: Error {
        case caseWithProperty(property: String)
    }
    class ClassError: Error {
        let property: String
        init(_ prop: String) {
            property = prop
        }
    }

    enum LogLevelSegment: Int {
        case debug = 0, info, notice, warn, error, critical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logServiceNameTextField.text = serviceName
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)
    }

    private var message: String {
        logMessageTextField.text!.isEmpty ? "message" : logMessageTextField.text!
    }

    @IBAction func didTapSendSingleLog(_ sender: Any) {
        sendOnceButton.disableFor(seconds: 0.5)

        let structError = StructError(property: "some value")
        let enumError = EnumError.caseWithProperty(property: "some value")
        let classError = ClassError("some value")
        let nsError = NSError(domain: "ExampleApp", code: 999, userInfo: [NSLocalizedDescriptionKey: "some value"])

        switch LogLevelSegment(rawValue: logLevelSegmentedControl.selectedSegmentIndex) {
        case .debug:    logger.debug(message, error: structError)
        case .info:     logger.info(message, error: enumError)
        case .notice:   logger.notice(message, error: classError)
        case .warn:     logger.warn(message, error: nsError)
        case .error:    logger.error(message, error: structError)
        case .critical: logger.critical(message, error: enumError)
        default:        assertionFailure("Unsupported `.selectedSegmentIndex` value: \(logLevelSegmentedControl.selectedSegmentIndex)")
        }
    }

    @IBAction func didTapSend10Logs(_ sender: Any) {
        send10xButton.disableFor(seconds: 0.5)

        switch LogLevelSegment(rawValue: logLevelSegmentedControl.selectedSegmentIndex) {
        case .debug:    repeat10x { logger.debug(message) }
        case .info:     repeat10x { logger.info(message) }
        case .notice:   repeat10x { logger.notice(message) }
        case .warn:     repeat10x { logger.warn(message) }
        case .error:    repeat10x { logger.error(message) }
        case .critical: repeat10x { logger.critical(message) }
        default:        assertionFailure("Unsupported `.selectedSegmentIndex` value: \(logLevelSegmentedControl.selectedSegmentIndex)")
        }
    }

    private func repeat10x(block: () -> Void) {
        (0..<10).forEach { _ in block() }
    }

    // MARK: - Stress testing

    var queues: [DispatchQueue] = []
    var loggers: [LoggerProtocol] = []

    @IBAction func didTapStressTest(_ sender: Any) {
        stressTestButton.disableFor(seconds: 10)

        loggers = (0..<5).map { index in
            return Logger.create(
                with: Logger.Configuration(
                    loggerName: "stress-logger-\(index)",
                    sendNetworkInfo: true
                )
            )
        }

        queues = (0..<5).map { index in
            return DispatchQueue(label: "com.datadoghq.example.stress-testing-queue\(index)")
        }

        let endDate = Date(timeIntervalSinceNow: 10) // 10s
        zip(loggers, queues).forEach { logger, queue in
            keepSendingLogs(on: queue, using: logger, every: 0.01, until: endDate)
        }
    }

    private func keepSendingLogs(on queue: DispatchQueue, using logger: LoggerProtocol, every timeInterval: TimeInterval, until endDate: Date) {
        if Date() < endDate {
            queue.asyncAfter(deadline: .now() + timeInterval) { [weak self] in
                logger.debug(self?.randomLogMessage() ?? "")
                self?.keepSendingLogs(on: queue, using: logger, every: timeInterval, until: endDate)
            }
        }
    }

    private let alphanumerics = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

    private func randomLogMessage() -> String {
        return String((0..<20).map { _ in alphanumerics.randomElement()! })
    }
}

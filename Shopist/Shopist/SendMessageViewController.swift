/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

class SendMessageViewController: UIViewController {

    @IBOutlet weak var logLevelSegmentedControl: UISegmentedControl!
    @IBOutlet weak var logMessageTextField: UITextField!
    @IBOutlet weak var logServiceNameTextField: UITextField!
    @IBOutlet weak var sendOnceButton: UIButton!
    @IBOutlet weak var send10xButton: UIButton!
    @IBOutlet weak var consoleTextView: UITextView!

    enum LogLevelSegment: Int {
        case debug = 0, info, notice, warn, error, critical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        hideKeyboardWhenTapOutside()
        startDisplayingDebugInfo(in: consoleTextView)
    }

    @IBAction func didTapSendSingleLog(_ sender: Any) {
        let message = logMessageTextField.text ?? ""
        switch LogLevelSegment(rawValue: logLevelSegmentedControl.selectedSegmentIndex) {
        case .debug:    logger.debug(message)
        case .info:     logger.info(message)
        case .notice:   logger.notice(message)
        case .warn:     logger.warn(message)
        case .error:    logger.error(message)
        case .critical: logger.critical(message)
        default:        assertionFailure("Unsupported `.selectedSegmentIndex` value: \(logLevelSegmentedControl.selectedSegmentIndex)")
        }
    }

    @IBAction func didTapSend10Logs(_ sender: Any) {
        let message = logMessageTextField.text ?? ""
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
}

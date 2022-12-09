/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Datadog

internal class CrashReportingViewController: UIViewController {
    @IBOutlet weak var sendingCrashReportLabel: UILabel!
    @IBOutlet weak var verticalStackView: UIStackView!

    private let objc = CrashReportingObjcHelpers()

    override func viewDidLoad() {
        super.viewDidLoad()

        let testScenario = (appConfiguration.testScenario as! CrashReportingBaseScenario)
        sendingCrashReportLabel.isHidden = !testScenario.hadPendingCrashReportDataOnStartup

        if testScenario.hadPendingCrashReportDataOnStartup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Datadog.flushAndDeinitialize()
            }
        } else {
            addCrashVariantButtons()
        }
    }

    private func addCrashVariantButtons() {
        func addButton(titled title: String, action selector: Selector) {
            let button = UIButton(type: .custom)
            button.backgroundColor = #colorLiteral(red: 0.4705882353, green: 0.2705882353, blue: 0.7098039216, alpha: 1)
            button.setTitle(title, for: .normal)
            button.layer.masksToBounds = true
            button.layer.cornerRadius = 7
            button.addTarget(nil, action: selector, for: .touchUpInside)
            button.showsTouchWhenHighlighted = true
            verticalStackView.addArrangedSubview(button)
        }

        addButton(titled: "Call fatalError()", action: #selector(callFatalError))
        addButton(titled: "Throw uncaught NSException", action: #selector(throwUncaughtNSException))
        addButton(titled: "Force try! Swift Error", action: #selector(forceTrySwiftError))
        addButton(titled: "Explicitly unwrap `nil` optional", action: #selector(explicitlyUnwrapOptionalNil))
        addButton(titled: "Implicitly unwrap `nil` optional", action: #selector(implicitlyUnwrapOptionalNil))
        addButton(titled: "Access array outside its bounds", action: #selector(accessArrayOutsideItsBounds))
        addButton(titled: "Dereference null pointer", action: #selector(dereferenceNullPointer))
        addButton(titled: "Infinite recursive call", action: #selector(infiniteRecursiveCall))
    }

    @objc func callFatalError() {
        fatalError("Called fatalError().")
    }

    @objc func throwUncaughtNSException() {
        objc.throwUncaughtNSException() // `[NSObject objectForKey:]: unrecognized selector sent to instance 0x...`
    }

    @objc func forceTrySwiftError() {
        struct Exception: Error, CustomDebugStringConvertible {
            let debugDescription = "Exception description."
        }

        func throwException() throws { throw Exception() }
        try! throwException()
    }

    @objc func explicitlyUnwrapOptionalNil() {
        let nilOptional: String? = nil
        _ = nilOptional! // Unexpectedly found nil while unwrapping an Optional value
    }

    @objc func implicitlyUnwrapOptionalNil() {
        let nilOptional: String! = nil
        _ = nilOptional.lowercased() // Unexpectedly found nil while implicitly unwrapping an Optional value
    }

    @objc func accessArrayOutsideItsBounds() {
        _ = [1, 2, 3][10] // Fatal error: Index out of range.
    }

    @objc func dereferenceNullPointer() {
        objc.dereferenceNullPointer()
    }

    @objc func infiniteRecursiveCall() {
        _ = recursiveCall(parameter: 0)
    }

    private var heap: [String] = []

    func recursiveCall(parameter: Int) -> Int {
        if parameter > 1_000_000 {
            heap.append("abcdefghijkl")
            return recursiveCall(parameter: parameter - 1)
        } else if parameter <= 1_000_000 {
            heap.append("abcdefghijkl")
            return recursiveCall(parameter: parameter + 1)
        } else {
            return 0 // not reachable, but mutes compiler warning
        }
    }
}

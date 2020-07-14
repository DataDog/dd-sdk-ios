/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import UIKit

public protocol Instrumentable {
    func getInstrumentedName() -> String
}

public extension Instrumentable where Self: UIViewController {
    func getInstrumentedName() -> String {
        return UIViewControllerUtils.getInstrumentedName(for: self)
    }
}

internal class UIViewControllerSwizzler {
    let viewDidAppear: ViewDidAppear

    init(instrumentationMode: Datadog.Configuration.ViewControllerInstrumentationMode) throws {
        self.viewDidAppear = try ViewDidAppear(instrumentationMode: instrumentationMode)
    }

    func swizzle() {
        self.viewDidAppear.swizzle()
    }
}

internal class ViewDidAppear: MethodSwizzler <
    @convention(c) (UIViewController, Selector, Bool) -> Void,
    @convention(block) (UIViewController, Bool) -> Void
> {
    private static let selector = #selector(UIViewController.viewDidAppear)
    private let method: FoundMethod
    private let instrumentationMode: Datadog.Configuration.ViewControllerInstrumentationMode

    init(instrumentationMode: Datadog.Configuration.ViewControllerInstrumentationMode) throws {
        method = try Self.findMethod(with: Self.selector, in: UIViewController.self)
        self.instrumentationMode = instrumentationMode
    }

    func swizzle() {
        typealias BlockIMP = @convention(block) (UIViewController, Bool) -> Void
        swizzle(method) {  currentTypedImp -> BlockIMP in
            return { impSelf, impAnimated  in
                impSelf.registerViewAppeared(instrumentationMode: self.instrumentationMode)
                return currentTypedImp(impSelf, Self.selector, impAnimated)
            }
        }
    }
}

private extension UIViewController {
    func registerViewAppeared(instrumentationMode: Datadog.Configuration.ViewControllerInstrumentationMode) {
        guard let rootViewController = UIViewControllerUtils.getRootViewController(for: self.view) else {
            return
        }

        var viewControllerName: String
        switch instrumentationMode {
        case .userdefined:
            if let instrumentedViewController = rootViewController as? Instrumentable {
                viewControllerName = instrumentedViewController.getInstrumentedName()
            } else {
                return
            }
        case .automatic:
            viewControllerName = UIViewControllerUtils.getInstrumentedName(for: rootViewController)
        case .off:
            return
        }

        //Create real RUM Event
        print("Showed ViewController: \(viewControllerName)")
    }
}

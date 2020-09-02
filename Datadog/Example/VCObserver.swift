/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

func ddObserve(viewController: UIViewController) {
    _ = DDObserver(observe: viewController)
}

private class DDObserver: UIViewController {
    private lazy var parentDescription: String = {
        guard let parent = parent else {
            return ""
        }
        return "\(type(of: parent))"
    }()

    init(observe observedViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        observedViewController.addChild(self)
        view.isHidden = true
        observedViewController.view.addSubview(view)
        didMove(toParent: observedViewController)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        print("🏈  \(parentDescription) viewDidLoad()")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("🏈  \(parentDescription) viewWillAppear()")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("🏈  \(parentDescription) viewDidAppear()")
    }
}

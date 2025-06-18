/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import SRFixtures

struct SwiftUIFixture: FixtureProtocol {
    private let _instantiateViewController: () -> UIViewController

    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
        _instantiateViewController = {
            UIHostingController(rootView: content())
        }
    }

    func instantiateViewController() -> UIViewController {
        _instantiateViewController()
    }
}

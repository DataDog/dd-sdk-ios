/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

internal class UnsupportedViewsViewController: UIViewController {
    
    @IBOutlet weak var swiftUIContainer: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()

        let hostingController = UIHostingController(rootView: TestView())
        addChild(hostingController)
        swiftUIContainer.addSubview(hostingController.view)
        hostingController.view.frame = swiftUIContainer.bounds
        hostingController.didMove(toParent: self)
    }
}

import SwiftUI

fileprivate struct TestView: View {
    var body: some View {
        VStack {
            Text("Title")
                .font(.title)

            Rectangle()
                .frame(width: 120, height: 16)
                .foregroundColor(.blue)
                .cornerRadius(8)
        }
    }
}


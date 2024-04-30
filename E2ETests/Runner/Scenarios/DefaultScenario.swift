/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import SwiftUI

/// The default scenario will present the list of Synthetic scenarios to run in development mode.
/// To skip this screen, you can set the `E2E_SCENARIO` environment variable with the name
/// the desired scenario.
struct DefaultScenario: Scenario {
    func start(info: TestInfo) -> UIViewController {
        UIHostingController(rootView: ContentView(info: info))
    }

    struct ContentView: View {
        let info: TestInfo

        var body: some View {
            NavigationView {
                List(SyntheticScenario.allCases, id: \.rawValue) { scenario in
                    NavigationLink {
                        ScenarioView(info: info, scenario: scenario)
                    } label: {
                        Text(scenario.rawValue)
                    }
                }
                .navigationBarTitle("Scenarios")
            }
        }
    }

    struct ScenarioView: UIViewControllerRepresentable {
        let info: TestInfo
        let scenario: Scenario

        func makeUIViewController(context: Context) -> UIViewController {
            scenario.start(info: info)
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) { }
    }
}

#if DEBUG
struct DefaultScenario_Previews: PreviewProvider {
    static var previews: some View {
        DefaultScenario.ContentView(info: .empty)
    }
}
#endif

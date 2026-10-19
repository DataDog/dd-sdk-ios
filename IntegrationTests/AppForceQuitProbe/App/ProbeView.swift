/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2026-Present Datadog, Inc.
 */

import SwiftUI
import UIKit

internal struct ProbeScreen: View {
    @ObservedObject var capture = ProbeCapture.shared
    @State private var trial = ""
    @State private var pendingFault: String?

    var body: some View {
        Form {
            Section(header: Text("App force quit evidence probe")) {
                Text("Local observations only. KSCrash enabled. Reporter lifecycle is an unvalidated hypothesis.")
                TextField("Host trial ID", text: $trial)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                .accessibilityIdentifier("trialID")
                Button("Set trial ID") {
                    capture.trialID = trial
                    capture.record("trial_assigned")
                }
                Text(capture.status).font(.system(.caption, design: .monospaced)).accessibilityIdentifier(
                    "probeStatus"
                )
                Button("Inspect and export JSON") {
                    guard let url = capture.export(), let presenter = presenter() else {
                        return
                    }
                    let controller = UIActivityViewController(
                        activityItems: [url],
                        applicationActivities: nil
                    )
                    controller.popoverPresentationController?.sourceView = presenter.view
                    presenter.present(controller, animated: true)
                }.accessibilityIdentifier("exportJSON")
                Button("Open another window on iPad") {
                    UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil)
                }
                Button("Verify reporter read refusal") { capture.verifyReporterRefusal() }
                Button("Restore startup reporter evidence") { capture.restoreReporterEvidence() }
            }
            Section(header: Text("Faults affect this dedicated probe only")) {
                ForEach(["managed_crash", "native_crash", "hang_5s", "fatal_hang", "memory"], id: \.self) { name in
                    Button(name) { pendingFault = name }.accessibilityIdentifier(name)
                }
                Button("Stop memory pressure") { capture.fault("stop_memory") }
            }
        }
        .alert(
            "Run controlled fault?",
            isPresented: Binding(get: { pendingFault != nil }, set: { if !$0 { pendingFault = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingFault = nil }
            Button("Run fault", role: .destructive) {
                if let name = pendingFault {
                    pendingFault = nil
                    capture.fault(name)
                }
            }
        } message: {
            Text(
                "Export prior evidence first. A hang or memory test may require manually removing this probe from the app switcher."
            )
        }
    }

    private func presenter() -> UIViewController? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
    }
}

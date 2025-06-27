/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogCore

/// Marks current RUM session as ended by starting and stopping one more RUM View ("end view"):
/// - starting the "end view" will mark the previous active view in the session as "eventually inactive",
/// - stopping the "end view" will mark it itself as "inactive".
///
/// Note: calling this method does not necessarily mean the end of RUM events processing. Some views in the current RUM session
/// could be still awaiting their resources completion (ref.: _RUMM-1779 Keep view active as long as we have ongoing resources_).
/// In result of this call, such views will be marked "eventually inactive" right away and will receive the "inactive" flag upon their last resource completion.
internal func markRUMSessionAsEnded() {
    rumMonitor.startView(key: Environment.Constants.rumSessionEndViewName)
    rumMonitor.stopView(key: Environment.Constants.rumSessionEndViewName)

    // Show utility view to indicate  in UI that current RUM session
    // was marked as ended (`UIHostingController` is excluded from instrumentation by default):
    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
        window.rootViewController = UIHostingController(rootView: RUMSessionEndView())
    }
}

private struct RUMSessionEndView: View {
    var body: some View {
        VStack(alignment: .center) {
            Text("RUM Session has ended")
                .font(.headline)
                .fontWeight(.bold)
            Divider()
            Text("This view is only displayed to finish the previous RUM view. " +
                 "Previous views could be still awaiting for their resources completion, but will finish soon.")
                .font(.subheadline)
                .fontWeight(.light)
            Divider()
        }
        .padding()
    }
}

/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogCore

@available(iOS 13, tvOS 13,*)
internal class DebugBackgroundEventsViewController: UIHostingController<DebugBackgroundEventsView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: DebugBackgroundEventsView())
    }
}

@available(iOS 13, tvOS 13,*)
private class DebugBackgroundEventsViewModel: ObservableObject {
    private let locationMonitor: BackgroundLocationMonitor

    @Published var isLocationMonitoringON = false
    @Published var willCrashDuringNextBackgroundLaunch = false
    @Published var willCrashOnNextBackgroundEvent = false
    @Published var authorizationStatus = ""

    init() {
        locationMonitor = backgroundLocationMonitor!
        isLocationMonitoringON = locationMonitor.isStarted
        authorizationStatus = locationMonitor.currentAuthorizationStatus
        locationMonitor.onAuthorizationStatusChange = { [weak self] newStatus in
            self?.authorizationStatus = newStatus
        }
        willCrashDuringNextBackgroundLaunch = locationMonitor.shouldCrashDuringNextBackgroundLaunch
        willCrashOnNextBackgroundEvent = locationMonitor.shouldCrashOnNextBackgroundEvent
    }

    func startLocationMonitoring() {
        locationMonitor.startMonitoring()
        isLocationMonitoringON = locationMonitor.isStarted
    }

    func stopLocationMonitoring() {
        locationMonitor.stopMonitoring()
        isLocationMonitoringON = locationMonitor.isStarted
    }

    func toggleCrashDuringNextBackgroundLaunch() {
        locationMonitor.setCrashDuringNextBackgroundLaunch(!locationMonitor.shouldCrashDuringNextBackgroundLaunch)
        willCrashDuringNextBackgroundLaunch = locationMonitor.shouldCrashDuringNextBackgroundLaunch
    }

    func toggleCrashOnNextBackgroundEvent() {
        locationMonitor.setCrashOnNextBackgroundEvent(!locationMonitor.shouldCrashOnNextBackgroundEvent)
        willCrashOnNextBackgroundEvent = locationMonitor.shouldCrashOnNextBackgroundEvent
    }
}

@available(iOS 13, tvOS 13,*)
internal struct DebugBackgroundEventsView: View {
    @ObservedObject private var viewModel = DebugBackgroundEventsViewModel()

    var body: some View {
        VStack(spacing: 18) {
            Text("CLLocationManager")
                .font(.headline)
                .padding()
            Divider()
            HStack {
                Text("Authorization Status:")
                    .font(.body).fontWeight(.light)
                Spacer()
                Text(viewModel.authorizationStatus)
                    .font(.body)
            }
            HStack {
                Text("Location Monitoring:")
                    .font(.body).fontWeight(.light)
                Spacer()
                if #available(iOS 14, tvOS 14, *) {
                    if viewModel.isLocationMonitoringON {
                        ProgressView().padding(.trailing, 8)
                    }
                }
                Button(viewModel.isLocationMonitoringON ? "STOP" : "START") {
                    if viewModel.isLocationMonitoringON {
                        viewModel.stopLocationMonitoring()
                    } else {
                        viewModel.startLocationMonitoring()
                    }
                }
            }
            Divider()
            HStack {
                Text("Crash during next background launch:").font(.footnote).fontWeight(.light)
                Spacer()
                Button(viewModel.willCrashDuringNextBackgroundLaunch ? "🔥 ENABLED" : "DISABLED") {
                    viewModel.toggleCrashDuringNextBackgroundLaunch()
                }
            }
            HStack {
                Text("Crash on next background event:").font(.footnote).fontWeight(.light)
                Spacer()
                Button(viewModel.willCrashOnNextBackgroundEvent ? "🔥 ENABLED" : "DISABLED") {
                    viewModel.toggleCrashOnNextBackgroundEvent()
                }
            }
            Divider()
            Text("Above settings are preserved between application launches, so they are also effective when app is launched in the background due to **significant** location change.")
                .font(.footnote)
            Spacer()
        }
        .buttonStyle(DatadogButtonStyle())
        .padding()
    }
}

// MARK - Preview

@available(iOS 13, tvOS 13,*)
internal struct DebugBackgroundEventsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DebugBackgroundEventsView()
                .previewLayout(.fixed(width: 400, height: 500))
                .preferredColorScheme(.light)
            DebugBackgroundEventsView()
                .previewLayout(.fixed(width: 400, height: 500))
                .preferredColorScheme(.dark)
        }
    }
}

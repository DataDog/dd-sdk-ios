/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogRUM
import SwiftUI

@MainActor
struct RUMManualContentView: View {
    @State private var eventType: RUMEvent
    @State private var viewName: String
    @State private var actionType: RUMActionType
    @State private var actionURL: String
    @State private var resourceURL: String
    @State private var errorMessage: String

    @State private var eventsPerBatch: Int
    @State private var interval: TimeInterval
    @State private var isRepeating: Bool

    @State private var isSending: Bool
    @State private var eventsCount: Int
    @State private var sendingTask: Task<Void, Never>?

    private var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }

    init() {
        eventType = .view
        viewName = "FooViewController"
        actionType = .tap
        actionURL = "actionEventTitle"
        resourceURL = "https://api.shopist.io/checkout.json"
        errorMessage = "iOS benchmark debug error message"
        eventsPerBatch = 5
        interval = 2.0
        isRepeating = false
        isSending = false
        eventsCount = 0
    }

    var body: some View {
        VStack {
            Form {
                Picker("Select RUM event", selection: $eventType) {
                    ForEach(RUMEvent.allCases, id: \.self) { event in
                        Text(event.rawValue)
                    }
                }

                eventConfiguration(for: eventType)

                Section(header: Text("Sending configuration")) {
                    HStack {
                        Text("Events per Second:")
                        Spacer()
                        TextField("Events/s", value: $eventsPerBatch, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $eventsPerBatch, in: 1 ... 100_000, step: 5)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Interval (sec):")
                        Spacer()
                        TextField("Interval:", value: $interval, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $interval, in: 1 ... 100, step: 1)
                            .frame(width: 80)
                    }
                    Toggle("Repeat sending events", isOn: $isRepeating)
                        .tint(Color.purple)
                }

                Button {
                    isSending ? stopSending() : startSending()
                } label: {
                    Text(isSending ? "Stop" : "Send")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(isSending ? Color.purple.opacity(0.8) : Color.purple)
                        .cornerRadius(8)
                }
                .listRowBackground(EmptyView())
                .listRowInsets(EdgeInsets())

                VStack(alignment: .center) {
                    Text("Events sent: \(eventsCount)")
                        .padding(.vertical, 20)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(EmptyView())
                .listRowInsets(EdgeInsets())
            }
        }
        .onDisappear {
            stopSending()
        }
    }

    @ViewBuilder
    private func eventConfiguration(for event: RUMEvent) -> some View {
        switch event {
        case .view:
            Section(header: Text("View event configuration")) {
                TextField("View name", text: $viewName)
            }
        case .action:
            Section(header: Text("Action event configuration")) {
                TextField("View name", text: $viewName)
                Picker("Action type", selection: $actionType) {
                    ForEach(RUMActionType.allCases, id: \.self) { type in
                        Text(type.toString).tag(type)
                    }
                }
                TextField("Action url", text: $actionURL)
            }
        case .resource:
            Section(header: Text("Resource event configuration")) {
                TextField("View name", text: $viewName)
                TextField("Resource url", text: $resourceURL)
            }
        case .error:
            Section(header: Text("Error event configuration")) {
                TextField("View name", text: $viewName)
                TextField("Error message", text: $errorMessage)
            }
        }
    }

    /// Starts the RUM events sending process based on the current configuration.
    /// - If repeating is enabled, starts a task that calls `sendEvents` at the configured interval
    /// - If repeating is disabled, sends a single batch of events and stops
    private func startSending() {
        isSending = true

        if isRepeating {
            let sleepInterval = interval
            sendingTask = Task {
                while !Task.isCancelled && isSending {
                    sendEvents()
                    try? await Task.sleep(for: .seconds(sleepInterval))
                }
            }
        } else {
            sendEvents()
            isSending = false
        }
    }

    /// Stops the RUM events sending process.
    private func stopSending() {
        isSending = false
        sendingTask?.cancel()
        sendingTask = nil
    }

    /// Sends a batch of RUM events based on the selected event type.
    private func sendEvents() {
        for _ in 1 ... eventsPerBatch {
            switch eventType {
            case .view:
                sendViewEvent()
            case .action:
                sendActionEvent()
            case .resource:
                sendResourceEvent()
            case .error:
                sendErrorEvent()
            }
            eventsCount += 1
        }
    }

    /// Creates and sends a view event.
    private func sendViewEvent() {
        rumMonitor.startView(key: viewName)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            rumMonitor.stopView(key: viewName)
        }
    }

    /// Creates and sends an action event.
    private func sendActionEvent() {
        rumMonitor.startView(key: viewName)
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            rumMonitor.addAction(type: actionType, name: actionURL)
            try? await Task.sleep(nanoseconds: 300_000_000)
            rumMonitor.stopView(key: viewName)
        }
    }

    /// Creates and sends a resource event.
    private func sendResourceEvent() {
        guard let url = URL(string: resourceURL) else {
            return
        }
        let request = URLRequest(url: url)
        rumMonitor.startResource(
            resourceKey: "/resource/1",
            request: request
        )

        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            rumMonitor.stopResource(
                resourceKey: "/resource/1",
                response: HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )!
            )
        }
    }

    /// Creates and sends an error event.
    private func sendErrorEvent() {
        rumMonitor.addError(message: errorMessage, source: .source)
    }
}

// MARK: - Private helpers

enum RUMEvent: String, CaseIterable, Sendable {
    case view = "View"
    case action = "Action"
    case resource = "Resource"
    case error = "Error"
}

extension RUMActionType {
    init(string: String) {
        switch string {
        case "tap": self = .tap
        case "scroll": self = .scroll
        case "swipe": self = .swipe
        case "custom": self = .custom
        default: self = RUMActionType.default
        }
    }

    var toString: String {
        switch self {
        case .tap: "tap"
        case .click: "click"
        case .scroll: "scroll"
        case .swipe: "swipe"
        case .custom: "custom"
        }
    }

    static let `default`: RUMActionType = .custom
}

#Preview {
    RUMManualContentView()
}

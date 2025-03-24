/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogRUM
import SwiftUI

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
    @State private var timer: Timer?

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

                Button(action: isSending ? stopSending : startSending) {
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
    /// - If repeating is enabled, sets up a timer that calls `sendEvents` at the configured interval
    /// - If repeating is disabled, sends a single batch of events and stops
    private func startSending() {
        isSending = true

        if isRepeating {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                if !isSending {
                    stopSending()
                    return
                }
                sendEvents()
            }
        } else {
            sendEvents()
            isSending = false
        }
    }

    /// Stops the RUM events sending process.
    private func stopSending() {
        isSending = false
        timer?.invalidate()
        timer = nil
    }

    /// Sends a batch of RUM events asynchronously based on the selected event type.
    private func sendEvents() {
        DispatchQueue.global(qos: .userInitiated).async {
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

                DispatchQueue.main.async {
                    eventsCount += 1
                }
            }
        }
    }

    /// Creates and sends a view event.
    /// - Creates a view controller with the specified URL
    /// - Starts a view event
    /// - Stops the view event after 0.5 seconds
    private func sendViewEvent() {
        rumMonitor.startView(key: viewName)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(key: viewName)
        }
    }

    /// Creates and sends an action event.
    /// - Creates a view controller with the specified URL
    /// - Starts a view event
    /// - Adds an action event after 0.2 seconds with the specified type and URL
    /// - Stops the view event after 0.5 seconds
    private func sendActionEvent() {
        rumMonitor.startView(key: viewName)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            rumMonitor.addAction(type: actionType, name: actionURL)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            rumMonitor.stopView(key: viewName)
        }
    }

    /// Creates and sends a resource event.
    /// - Creates a view controller with the specified URL
    /// - Starts a view event
    /// - Creates and starts a resource request with the specified URL
    /// - Stops the resource event after 0.2 seconds with a successful response
    /// - Stops the view event after 0.5 seconds
    private func sendResourceEvent() {
        guard let url = URL(string: resourceURL) else {
            return
        }
        let request = URLRequest(url: url)
        rumMonitor.startResource(
            resourceKey: "/resource/1",
            request: request
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
    /// - Creates a view controller with the specified URL
    /// - Starts a view event
    /// - Adds an error event after 0.2 seconds with the specified message
    /// - Stops the view event after 0.5 seconds
    private func sendErrorEvent() {
        rumMonitor.addError(message: errorMessage, source: .source)
    }
}

// MARK: - Private helpers

enum RUMEvent: String, CaseIterable {
    case view = "View"
    case action = "Action"
    case resource = "Resource"
    case error = "Error"
}

extension RUMActionType: CaseIterable {
    public static var allCases: [RUMActionType] = [
        .click,
        .tap,
        .scroll,
        .swipe,
        .custom,
    ]

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

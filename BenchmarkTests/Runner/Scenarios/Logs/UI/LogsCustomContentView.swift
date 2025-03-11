/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogLogs
import SwiftUI

struct LogsCustomContentView: View {
    @State private var logMessage: String
    @State private var logLevel: String
    @State private var logsPerBatch: Int
    @State private var interval: Double
    @State private var isRepeating: Bool
    @State private var payloadSize: String
    @State private var isLogging: Bool

    private let logger: LoggerProtocol

    init() {
        logMessage = "Hello from the iOS Benchmark app!"
        logLevel = "INFO"
        logsPerBatch = 10
        interval = 5
        isRepeating = false
        payloadSize = "Small"
        isLogging = false

        logger = Logger.create()
    }

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Log Configuration")) {
                    TextField("Log Message", text: $logMessage)
                    Picker("Log Level", selection: $logLevel) {
                        ForEach(logLevels, id: \.1) { level in
                            Text(level.0).tag(level.0)
                        }
                    }
                    Picker("Payload Size", selection: $payloadSize) {
                        ForEach(payloadSizes, id: \.0) { size in
                            Text(size.0).tag(size.0)
                        }
                    }
                }

                Section(header: Text("Logging Frequency")) {
                    HStack {
                        Text("Logs per Second:")
                        Spacer()
                        TextField("Enter logs/s", value: $logsPerBatch, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $logsPerBatch, in: 1 ... 100_000, step: 10)
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
                    Toggle("Repeat Logging", isOn: $isRepeating)
                        .tint(Color.purple)
                }

                Section {
                    Button(action: isLogging ? stopLogging : startLogging) {
                        Text(isLogging ? "Stop Logging" : "Start Logging")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(isLogging ? Color.purple.opacity(0.8) : Color.purple)
                            .cornerRadius(8)
                    }
                }
                .listRowBackground(EmptyView())
                .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(10)
        }
    }

    /// Executes a batch of log entries asynchronously.
    /// - Parameters:
    ///   - selectedLogLevel: The log level  to use for logging.
    ///   - attributes: The payload attributes corresponding to the selected payload size.
    func logBatch(selectedLogLevel: LogLevel, attributes: [String: Encodable]) {
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 1...self.logsPerBatch {
                self.logger.log(level: selectedLogLevel, message: self.logMessage, error: nil, attributes: attributes)
            }
        }
    }

    /// Starts the logging process based on the current configuration.
    /// - If repeating logging is enabled, it sets up a repeating timer that calls `logBatch` at the configured interval.
    /// - Otherwise, it sends a single batch of logs.
    func startLogging() {
        isLogging = true

        guard let selectedLogLevel = logLevels.first(where: { $0.0 == self.logLevel }),
              let attributes = payloadSizes.first(where: { $0.0 == self.payloadSize }) else { return }

        if isRepeating {
            Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
                if !self.isLogging {
                    timer.invalidate()
                    return
                }
                self.logBatch(selectedLogLevel: selectedLogLevel.1, attributes: attributes.1)
            }
        } else {
            logBatch(selectedLogLevel: selectedLogLevel.1, attributes: attributes.1)
            isLogging = false
        }
    }

    /// Stops the logging process
    func stopLogging() {
        isLogging = false
    }
}

#Preview {
    LogsCustomContentView()
}

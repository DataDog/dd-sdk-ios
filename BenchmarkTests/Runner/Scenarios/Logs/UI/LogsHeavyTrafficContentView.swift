/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogLogs

struct LogsHeavyTrafficContentView: View {
    @State private var logMessage: String
    @State private var logLevel: String
    @State private var logsPerBatch: Int
    @State private var payloadSize: String

    private var logger: LoggerProtocol!

    init() {
        logMessage = "Hello from the iOS Benchmark app!"
        logsPerBatch = 10
        payloadSize = "Small"
        logLevel = "INFO"

        logger = Logger.create()
    }

    var body: some View {
        NavigationStack {
            List(0..<1_000, id: \.self) { index in
               let url = URL(string: "https://picsum.photos/800/600?random=\(index)")!
               HeavyImageRow(imageURL: url)
                   .onAppear {
                       log()
                   }
            }
            .navigationTitle("Heavy Traffic")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: LogsHeavyTrafficConfigView(logMessage: $logMessage, logLevel: $logLevel, logsPerBatch: $logsPerBatch, payloadSize: $payloadSize)) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .tint(.purple)
    }
    
    /// Sends a batch of log messages using the current configuration.
    func log() {
        guard let selectedLogLevel = logLevels[logLevel],
              let attributes = payloadSizes[payloadSize] else { return }

        for _ in 1 ... self.logsPerBatch {
            self.logger.log(level: selectedLogLevel, message: self.logMessage, error: nil, attributes: attributes)
        }
    }
}

struct HeavyImageRow: View {
    let imageURL: URL

    var body: some View {
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(height: 100)
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(height: 100)
                    .clipped()
            case .failure:
                Color.gray
                    .overlay(Text("Failed to load image")
                        .foregroundColor(.white))
                    .frame(height: 100)
            @unknown default:
                EmptyView()
            }
        }
        .cornerRadius(8)
        .padding(.vertical, 5)
    }
}

struct LogsHeavyTrafficConfigView: View {
    @Binding private var logMessage: String
    @Binding private var logLevel: String
    @Binding private var logsPerBatch: Int
    @Binding private var payloadSize: String

    init(logMessage: Binding<String>, logLevel: Binding<String>, logsPerBatch: Binding<Int>, payloadSize: Binding<String>) {
        self._logMessage = logMessage
        self._logLevel = logLevel
        self._logsPerBatch = logsPerBatch
        self._payloadSize = payloadSize
    }

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Log Configuration")) {
                    TextField("Log Message", text: $logMessage)
                    Picker("Log Level", selection: $logLevel) {
                        ForEach(Array(logLevels.keys), id: \.self) { level in
                            Text(level)
                        }
                    }
                    Picker("Payload Size", selection: $payloadSize) {
                        ForEach(Array(payloadSizes.keys), id: \.self) { size in
                            Text(size)
                        }
                    }
                }

                Section(header: Text("Logging Frequency")) {
                    HStack {
                        Text("Logs per Image:")
                        Spacer()
                        TextField("Enter logs/s", value: $logsPerBatch, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $logsPerBatch, in: 1 ... 100_000, step: 10)
                            .frame(width: 80)
                    }
                }
            }
            .listSectionSpacing(10)
        }
    }
}

#Preview {
    LogsHeavyTrafficContentView()
}

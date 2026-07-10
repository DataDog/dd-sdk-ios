/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogRUM
import SwiftUI

struct ProfilingContentView: View {
    private static let durationFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    @State private var signal: ProfilingSignal = .longTask
    @State private var longTaskDuration: TimeInterval = 0.2
    @State private var appHangDuration: TimeInterval = 1.0
    @State private var operationName: String = "benchmark.operation"
    @State private var operationDuration: TimeInterval = 2.0
    @State private var shouldFailOperation: Bool = false

    @State private var isSending: Bool = false
    @State private var eventsCount: Int = 0
    @State private var lastSignalSummary: String = ""
    @State private var sendTask: Task<Void, Never>?

    private var rumMonitor: RUMMonitorProtocol { RUMMonitor.shared() }

    init() {
        // Block TTID for 1 second to have App launch profiling data.
        Thread.sleep(forTimeInterval: 1)
    }

    var body: some View {
        Form {
            Section(header: Text("Profiling signal")) {
                Picker("Select signal", selection: $signal) {
                    ForEach(ProfilingSignal.allCases, id: \.self) { signal in
                        Text(signal.rawValue)
                    }
                }
            }

            signalConfiguration()

            Button(action: startSending) {
                Text("Send")
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Constants.contentPadding)
                    .background(isSending ? Color.purple.opacity(0.8) : Color.purple)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .padding(.horizontal, Constants.contentPadding)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            VStack(alignment: .center, spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .opacity(isSending ? 1 : 0)

                Text("Signals sent: \(eventsCount)")

                Text(lastSignalSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Constants.contentPadding)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .trackRUMView(name: Constants.viewName)
        .onDisappear {
            sendTask?.cancel()
            sendTask = nil
        }
    }

    @ViewBuilder
    private func signalConfiguration() -> some View {
        switch signal {
        case .longTask:
            Section(header: Text("Long task configuration")) {
                durationRow(
                    title: "Main thread work (sec)",
                    placeholder: "Duration",
                    value: $longTaskDuration,
                    range: 0.1 ... 5.0,
                    step: 0.1
                )

                Text("Runs a CPU-heavy block on the main thread so Profiling can capture a long task.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

        case .appHang:
            Section(header: Text("App hang configuration")) {
                durationRow(
                    title: "Blocked main thread (sec)",
                    placeholder: "Duration",
                    value: $appHangDuration,
                    range: 0.5 ... 10.0,
                    step: 0.25
                )

                Text("Uses a longer CPU-heavy block on the main thread to cross the app hang threshold.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

        case .operation:
            Section(header: Text("Operation configuration")) {
                TextField("Operation name", text: $operationName)

                durationRow(
                    title: "Background work (sec)",
                    placeholder: "Duration",
                    value: $operationDuration,
                    range: 0.25 ... 15.0,
                    step: 0.25
                )

                Toggle("Fail operation at the end", isOn: $shouldFailOperation)
                    .tint(Color.purple)

                Text("Starts a sampled RUM operation and keeps a CPU-heavy block running in a background task while the operation is active.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func durationRow(
        title: String,
        placeholder: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
        step: TimeInterval
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)

            HStack(spacing: 12) {
                TextField(placeholder, value: value, formatter: Self.durationFormatter)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: .infinity)
                    .keyboardType(.decimalPad)

                Stepper("", value: value, in: range, step: step)
                    .frame(maxWidth: .infinity)
                    .labelsHidden()
            }
        }
    }
}

private extension ProfilingContentView {
    func startSending() {
        guard isSending == false else {
            return
        }

        isSending = true
        let configuration = ProfilingConfiguration(
            signal: signal,
            longTaskDuration: longTaskDuration,
            appHangDuration: appHangDuration,
            operationName: operationName,
            operationDuration: operationDuration,
            shouldFailOperation: shouldFailOperation
        )

        sendTask = Task(priority: .userInitiated) {
            if configuration.signal.blocksMainThread {
                try? await Task.sleep(nanoseconds: Constants.progressViewLeadTime)
            }

            await send(configuration)

            await MainActor.run {
                isSending = false
                sendTask = nil
            }
        }
    }

    func send(_ configuration: ProfilingConfiguration) async {
        switch configuration.signal {
        case .longTask:
            sendLongTask(using: configuration)
        case .appHang:
            sendAppHang(using: configuration)
        case .operation:
            await sendOperation(using: configuration)
        }
    }

    func sendLongTask(using configuration: ProfilingConfiguration) {
        runHighProcessingBlock(for: configuration.longTaskDuration)
        recordSignal(label: "Long task", duration: configuration.longTaskDuration)
    }

    func sendAppHang(using configuration: ProfilingConfiguration) {
        runHighProcessingBlock(for: configuration.appHangDuration)
        recordSignal(label: "App hang", duration: configuration.appHangDuration)
    }

    func sendOperation(using configuration: ProfilingConfiguration) async {
        let trimmedName = configuration.operationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty ? "benchmark.operation" : trimmedName

        rumMonitor.startOperation(
            name: name,
            options: ProfilingOptions(sampleRate: .maxSampleRate)
        )

        _ = await Task.detached(priority: .userInitiated) {
            await runHighProcessingBlock(for: configuration.operationDuration)
        }.value

        if configuration.shouldFailOperation {
            rumMonitor.failOperation(name: name, reason: .other)
        } else {
            rumMonitor.succeedOperation(name: name)
        }

        recordSignal(
            label: configuration.shouldFailOperation ? "Failed operation" : "Operation",
            duration: configuration.operationDuration
        )
    }

    @discardableResult
    func runHighProcessingBlock(for duration: TimeInterval) -> Double {
        let deadline = ProcessInfo.processInfo.systemUptime + max(duration, Constants.minimumWorkDuration)
        var accumulator = 0.0
        var current = 1.0

        while ProcessInfo.processInfo.systemUptime < deadline {
            for _ in 0 ..< Constants.workChunkSize {
                accumulator += sin(current) * cos(current / 3)
                current += 0.0001
            }
        }

        return accumulator
    }

    func recordSignal(label: String, duration: TimeInterval) {
        eventsCount += 1
        lastSignalSummary = "\(label) finished in \(String(format: "%.2f", duration))s."
    }
}

private enum ProfilingSignal: String, CaseIterable {
    case longTask = "Long Task"
    case appHang = "App Hang"
    case operation = "Operation"

    var blocksMainThread: Bool {
        switch self {
        case .longTask, .appHang:
            true
        case .operation:
            false
        }
    }
}

private struct ProfilingConfiguration {
    let signal: ProfilingSignal
    let longTaskDuration: TimeInterval
    let appHangDuration: TimeInterval
    let operationName: String
    let operationDuration: TimeInterval
    let shouldFailOperation: Bool
}

private enum Constants {
    static let viewName = "ProfilingBenchmarkView"
    static let minimumWorkDuration: TimeInterval = 0.05
    static let workChunkSize = 2_000
    static let contentPadding: CGFloat = 16
    static let progressViewLeadTime: UInt64 = 100_000_000
}

#Preview {
    ProfilingContentView()
}

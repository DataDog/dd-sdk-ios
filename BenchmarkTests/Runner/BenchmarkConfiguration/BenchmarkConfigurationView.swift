/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogProfiler

internal class BenchmarkViewModel: ObservableObject {
    struct ScenarioItem: Identifiable {
        let id: String
        let name: String
    }

    @Published var runDuration: String
    @Published var runType: String
    @Published var scenarios: [ScenarioItem]
    @Published var selectedScenario: ScenarioItem?
    @Published var showScenarioSelection: Bool

    @Published var skipUploads: Bool
    @Published var metricEnvTag: String

    @Published var isMemoryInstrumentEnabled: Bool
    @Published var memorySamplingInterval: Double

    @Published var showSummary: Bool

    var canGoNext: Bool {
        let hasScenario = selectedScenario != nil
        let hasAnyInstrument = isMemoryInstrumentEnabled
        return hasScenario && hasAnyInstrument
    }

    init(with benchmark: Benchmark = Benchmark()) {
        // Scenario:
        self.runDuration = String(benchmark.duration)
        self.runType = benchmark.runType.rawValue
        let allScenarios = Benchmark.Scenario.allCases.map { scenario in
            ScenarioItem(
                id: scenario.configuration.id,
                name: scenario.configuration.name
            )
        }
        self.scenarios = allScenarios
        self.selectedScenario = allScenarios.first { $0.id == benchmark.scenario?.configuration.id }
        self.showScenarioSelection = false

        // Metrics:
        self.skipUploads = benchmark.skipUploads
        self.metricEnvTag = benchmark.env.rawValue

        // Instruments:
        if let memoryInstrument: MemoryInstrumentConfiguration = benchmark.instruments.firstElement() {
            self.isMemoryInstrumentEnabled = true
            self.memorySamplingInterval = memoryInstrument.samplingInterval
        } else {
            self.isMemoryInstrumentEnabled = false
            self.memorySamplingInterval = 1
        }
        self.showSummary = false
    }

    var benchmark: Benchmark {
        return Benchmark(
            duration: TimeInterval(runDuration) ?? 0,
            runType: Benchmark.RunType(rawValue: runType) ?? .baseline,
            skipUploads: skipUploads,
            scenario: selectedScenario.map { selected in
                Benchmark.Scenario.allCases.first { $0.configuration.id == selected.id } ?? .debug
            },
            instruments: {
                var enabled: [Benchmark.Instrument] = []
                if isMemoryInstrumentEnabled {
                    enabled.append(.memory(samplingInterval: memorySamplingInterval))
                }
                return enabled
            }(),
            env: Benchmark.Env(rawValue: metricEnvTag) ?? .local
        )
    }
}

struct BenchmarkConfigurationView: View {
    @StateObject private var vm = BenchmarkViewModel()

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Scenario")) {
                        HStack {
                            Text("Duration [s]:")
                            TextField("Enter duration", text: $vm.runDuration)
                                .keyboardType(.numberPad)
                        }
                        HStack {
                            Text("Type")
                            Picker("", selection: $vm.runType) {
                                Text(Benchmark.RunType.baseline.rawValue).tag(Benchmark.RunType.baseline.rawValue)
                                Text(Benchmark.RunType.instrumented.rawValue).tag(Benchmark.RunType.instrumented.rawValue)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                        NavigationLink(
                            destination: ScenarioSelectionView(
                                selectedScenario: $vm.selectedScenario,
                                showScenarioSelection: $vm.showScenarioSelection,
                                scenarios: vm.scenarios
                            )
                        ) {
                            Text(vm.selectedScenario?.name ?? "Select Scenario")
                        }
                    }

                    Section(header: Text("Metrics")) {
                        Toggle(isOn: $vm.skipUploads) {
                            Text("Skip upload")
                        }
                        HStack {
                            Text("env:").font(.system(.body, design: .monospaced))
                            Picker("", selection: $vm.metricEnvTag) {
                                Text(Benchmark.Env.local.rawValue).tag(Benchmark.Env.local.rawValue)
                                Text(Benchmark.Env.synthetics.rawValue).tag(Benchmark.Env.synthetics.rawValue)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                        }
                    }

                    Section(header: Text("Instruments")) {
                        Toggle(isOn: $vm.isMemoryInstrumentEnabled) {
                            Text("Memory")
                        }

                        if vm.isMemoryInstrumentEnabled {
                            VStack {
                                Text("Sampling Interval: \(vm.memorySamplingInterval, specifier: "%.1f") seconds")
                                    .font(.system(.footnote))
                                Slider(value: $vm.memorySamplingInterval, in: 0.1...5.0, step: 0.1)
                            }
                        }
                    }
                }

                Spacer()

                HStack {
                    NavigationLink(
                        destination: SummaryView(vm: SummaryViewModel(with: vm.benchmark)),
                        isActive: $vm.showSummary
                    ) {
                        Button(action: {
                            vm.showSummary = true
                        }) {
                            Text("NEXT")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(vm.canGoNext ? Color("DatadogPurple") : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!vm.canGoNext)
                }
                .padding()
            }
            .navigationBarTitle("Benchmark")
        }
    }
}

struct ScenarioSelectionView: View {
    typealias ScenarioItem = BenchmarkViewModel.ScenarioItem

    @Binding var selectedScenario: ScenarioItem?
    @Binding var showScenarioSelection: Bool

    var scenarios: [ScenarioItem]

    var body: some View {
        List(scenarios, id: \.id) { scenario in
            Button(action: {
                selectedScenario = scenario
                showScenarioSelection = false
            }) {
                HStack {
                    Text(scenario.name)
                    Spacer()
                    if scenario.id == selectedScenario?.id {
                        Image(systemName: "checkmark")
                            .foregroundColor(.purple)
                    }
                }
            }
        }
        .navigationBarTitle("Select Scenario", displayMode: .inline)
    }
}

struct BenchmarkConfigurationView_Previews: PreviewProvider {
    static var previews: some View {
        BenchmarkConfigurationView()
    }
}

extension Array {
    func firstElement<T>(of type: T.Type = T.self) -> T? {
        return compactMap({ $0 as? T }).first
    }
}

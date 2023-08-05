/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

internal class SummaryViewModel: ObservableObject {
    @Published var scenarioDescription: String
    @Published var instrumentDescriptions: [String]

    init(with benchmark: Benchmark) {
        self.scenarioDescription = """
        - Scenario: \(benchmark.scenario?.configuration.name ?? "???")
        - Run type: \(benchmark.runType.rawValue)
        - Duration: \(benchmark.duration)s
        - Skip benchmark data upload: \(benchmark.skipUploads)
        """
        self.instrumentDescriptions = benchmark.instrumentConfigurations.map { $0.description }
    }
}

struct SummaryView: View {
    @StateObject var vm: SummaryViewModel

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Scenario")) {
                        Text(vm.scenarioDescription)
                            .font(.system(.footnote, design: .monospaced))
                    }

                    Section(header: Text("Instruments")) {
                        if !vm.instrumentDescriptions.isEmpty {
                            Group {
                                List(vm.instrumentDescriptions, id: \.self) { Text($0) }
                            }
                            .font(.system(.caption2, design: .monospaced))
                        } else {
                            Text("None")
                        }
                    }
                }

                Spacer() // Add spacer to push the RUN button to the bottom

                HStack {
                    Button(action: {
                        // Handle the RUN button action here
                    }) {
                        Text("START")
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("DatadogPurple"))
                    .cornerRadius(10)
                }
                .padding()
            }
            .navigationBarTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SummaryView_Previews: PreviewProvider {
    static var previews: some View {
        SummaryView(
            vm: SummaryViewModel(
                with: Benchmark(
                    scenario: .debug,
                    instruments: [
                        .memory(samplingInterval: 10)
                    ]
                )
            )
        )
    }
}

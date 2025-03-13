/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogTrace
import SwiftUI

struct TraceContentView: View {
    @State private var operationName: String
    @State private var resourceName: String
    @State private var isError: Bool
    @State private var depth: Int
    @State private var childrenCount: Int
    @State private var childDelay: TimeInterval
    @State private var traceCount: Int
    @State private var isSending: Bool

    var tracer: OTTracer { Tracer.shared() }

    private let queue1 = DispatchQueue(label: "com.datadoghq.benchmark-tracing1")

    init() {
        operationName = "iOS Benchmark span operation"
        resourceName = "iOS Benchmark span resource"
        isError = false
        depth = 1
        childrenCount = 0
        childDelay = 100
        traceCount = 0
        isSending = false
    }

    var body: some View {
        VStack {
            Form {
                Section(header: Text("Span configuration")) {
                    TextField("Operation name", text: $operationName)
                    TextField("Resource name", text: $resourceName)
                    Toggle("Is Error", isOn: $isError)
                        .tint(.purple)
                }

                Section(header: Text("Complex span configuration")) {
                    HStack {
                        Text("Children count:")
                        Spacer()
                        TextField("Children count:", value: $childrenCount, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $childrenCount, in: 0 ... 100, step: 1)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Depth:")
                        Spacer()
                        TextField("Depth:", value: $depth, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $depth, in: 1 ... 100, step: 1)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Child delay (ms):")
                        Spacer()
                        TextField("Child delay:", value: $childDelay, formatter: NumberFormatter())
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 80)
                            .keyboardType(.numberPad)
                        Stepper("", value: $childDelay, in: 50 ... 10_000, step: 50)
                            .frame(width: 80)
                    }
                }

                Button(action: sendTrace) {
                    Text("Send")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .cornerRadius(8)
                }
                .listRowBackground(EmptyView())
                .listRowInsets(EdgeInsets())

                VStack(alignment: .center) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .opacity(isSending ? 1 : 0)
                        .padding()
                    Text("Traces sent: \(traceCount)")
                        .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(EmptyView())
                .listRowInsets(EdgeInsets())
            }
        }
    }

    /// Starts the tracing process based on the current configuration:
    /// 1. Creates a root span. with the given configuration.
    /// 2. Recursively generates child spans via `sendSpanTree`.
    /// 3. Finishes the root span and updates the trace counter.
    private func sendTrace() {
        DispatchQueue.main.async {
            isSending = true
        }

        queue1.async { [self] in
            let rootSpan = tracer.startSpan(operationName: operationName)
            rootSpan.setTag(key: SpanTags.resource, value: resourceName)

            if isError {
                rootSpan.log(
                    fields: [
                        OTLogFields.event: "error",
                        OTLogFields.errorKind: "Simulated error",
                        OTLogFields.message: "Describe what happened",
                        OTLogFields.stack: "Foo.swift:42",
                    ]
                )
            }

            Thread.sleep(forTimeInterval: childDelay / 1_000)

            sendSpanTree(parent: rootSpan, currentLevel: 0, maxDepth: depth)

            Thread.sleep(forTimeInterval: 0.5)
            rootSpan.finish()

            DispatchQueue.main.async {
                traceCount += 1
                isSending = false
            }
        }
    }

    /// Recursively generates a tree of child spans starting from the given parent span, waiting for `childDelay` between span creation.
    /// If the current level reaches `maxDepth` or if `childrenCount` is 0, recursion stops.
    /// - Parameters:
    ///   - parent: The parent span from which to create child spans.
    ///   - currentLevel: The current depth level in the span tree.
    ///   - maxDepth: The maximum depth (levels) for the span tree generation.
    private func sendSpanTree(parent: OTSpan, currentLevel: Int, maxDepth: Int) {
        guard currentLevel < maxDepth, childrenCount > 0 else { return }

        for i in 1 ... childrenCount {
            let childOperation = "\(operationName) - Child \(i) at level \(currentLevel + 1)"
            let childSpan = tracer.startSpan(operationName: childOperation, childOf: parent.context)

            Thread.sleep(forTimeInterval: childDelay / 1_000)

            sendSpanTree(parent: childSpan, currentLevel: currentLevel + 1, maxDepth: maxDepth)
            childSpan.finish()
        }
    }
}

#Preview {
    TraceContentView()
}

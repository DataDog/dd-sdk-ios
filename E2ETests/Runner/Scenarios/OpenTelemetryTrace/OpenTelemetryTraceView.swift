/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI
import OpenTelemetryApi

class DistributedTraceDelegate: NSObject, URLSessionDataDelegate {
}

class OpenTelemetryTraceViewController: UIHostingController<OpenTelemetryTraceView> {
    init(tracer: OpenTelemetryApi.Tracer, urlSession: URLSession) {
        super.init(rootView: OpenTelemetryTraceView(tracer: tracer, urlSession: urlSession))
    }

    @available(*, unavailable)
    @MainActor
    dynamic required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct OpenTelemetryTraceView: View {
    let tracer: OpenTelemetryApi.Tracer
    let urlSession: URLSession

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Local span, starts and ends in the same thread")) {
                        Button(action: {
                            tracer.spanBuilder(spanName: "Local Span").startSpan().end()
                        }) {
                            Text("Generate")
                        }
                    }

                    Section(header: Text("Distributed span, calling httpbin.org")) {
                        Button(action: {
                            Task {
                                let (_, response) = try await self.urlSession.data(from: .init(string: "https://httpbin.org/get")!)
                                guard let httpResponse = response as? HTTPURLResponse else {
                                    print("Invalid response")
                                    return
                                }

                                print("Response status code: \(httpResponse.statusCode)")
                            }
                        }) {
                            Text("Call httpbin.org/get")
                        }

                        Button(action: {
                            Task {
                                let (_, response) = try await self.urlSession.data(from: .init(string: "https://httpbin.org/status/500")!)
                                guard let httpResponse = response as? HTTPURLResponse else {
                                    print("Invalid response")
                                    return
                                }

                                print("Response status code: \(httpResponse.statusCode)")
                            }
                        }) {
                            Text("Call httpbin.org/status/500")
                        }
                    }

                    Section(header: Text("Async Await span, starts and ends in different threads")) {
                        Button(action: {
                            let span = tracer.spanBuilder(spanName: "Async Await Span").startSpan()
                            Task {
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                span.end()
                            }
                        }) {
                            Text("Generate")
                        }
                    }

                    Section(header: Text("Closure span, starts and ends in different threads")) {
                        Button(action: {
                            let span = tracer.spanBuilder(spanName: "Closure Span").startSpan()
                            DispatchQueue.main.async {
                                span.end()
                            }
                        }) {
                            Text("Generate")
                        }
                    }
                }
            }
            .navigationTitle("OpenTelemetry Trace")
        }
    }
}

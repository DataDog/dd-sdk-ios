/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogTrace

@available(iOS 14, *)
internal class DebugManualTraceInjectionViewController: UIHostingController<DebugManualTraceInjectionView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: DebugManualTraceInjectionView())
    }
}

private var currentSession: URLSession? = nil

@available(iOS 14.0, *)
internal struct DebugManualTraceInjectionView: View {
    enum TraceHeaderType: String, CaseIterable {
        case datadog = "Datadog"
        case w3c = "W3C"
        case b3Single = "B3-Single"
        case b3Multiple = "B3-Multiple"
    }

    @State private var spanName = "network request"
    @State private var requestURL = "http://127.0.0.1:8000"
    @State private var selectedTraceHeaderType: TraceHeaderType = .datadog
    @State private var sampleRate: Float = 100.0
    @State private var isRequestPending = false

    private let session: URLSession = URLSession(
        configuration: .ephemeral,
        delegate: DDURLSessionDelegate(),
        delegateQueue: nil
    )

    var body: some View {
        let isButtonDisabled = isRequestPending || spanName.isEmpty || requestURL.isEmpty

        VStack() {
            VStack(spacing: 8) {
                Text("Trace injection")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("After tapping \"SEND REQUEST\", a POST request will be sent to the given URL. The request will be traced using the chosen tracing header type and sample rate. A span with specified name will be sent to Datadog.")
                    .font(.caption.weight(.light))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()

            Form {
                Section(header: Text("Traced URL:")) {
                    TextField("", text: $requestURL)
                }
                Section(header: Text("Span name:")) {
                    TextField("", text: $spanName)
                }
                Picker("Trace header type:", selection: $selectedTraceHeaderType) {
                    ForEach(TraceHeaderType.allCases, id: \.self) { headerType in
                        Text(headerType.rawValue)
                    }
                }
                .pickerStyle(.inline)
                Section(header: Text("Trace sample Rate")) {
                    Slider(
                        value: $sampleRate,
                        in: 0...100, step: 1,
                        minimumValueLabel: Text("0"),
                        maximumValueLabel: Text("100")
                    ) {
                        Text("Sample Rate")
                    }
                }
            }

            Spacer()

            Button(action: { prepareAndSendRequest() }) {
                Text("SEND REQUEST")
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isButtonDisabled ? Color.gray : Color.datadogPurple)
            .cornerRadius(10)
            .disabled(isButtonDisabled)
            .padding(.horizontal, 8)
            .padding(.bottom, 30)
        }
    }

    private func prepareAndSendRequest() {
        guard let url = URL(string: requestURL) else {
            print("🔥 POST Request not sent - invalid url: \(requestURL)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let span = Tracer.shared().startRootSpan(operationName: spanName)

        switch selectedTraceHeaderType {
        case .datadog:
            let writer = HTTPHeadersWriter(sampleRate: sampleRate)
            Tracer.shared().inject(spanContext: span.context, writer: writer)
            writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        case .w3c:
            let writer = W3CHTTPHeadersWriter(
                sampleRate: sampleRate,
                tracestate: [:]
            )
            Tracer.shared().inject(spanContext: span.context, writer: writer)
            writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        case .b3Single:
            let writer = B3HTTPHeadersWriter(sampleRate: sampleRate, injectEncoding: .single)
            Tracer.shared().inject(spanContext: span.context, writer: writer)
            writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        case .b3Multiple:
            let writer = B3HTTPHeadersWriter(sampleRate: sampleRate, injectEncoding: .multiple)
            Tracer.shared().inject(spanContext: span.context, writer: writer)
            writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        }

        send(request: request) {
            span.finish()
            print("✅ Request sent to \(requestURL)")
        }
    }

    private func send(request: URLRequest, completion: @escaping () -> Void) {
        isRequestPending = true
        let task = session.dataTask(with: request) { _, _, _ in
            completion()
            DispatchQueue.main.async { self.isRequestPending = false }
        }
        task.resume()
    }
}

// MARK - Preview

@available(iOS 14.0, *)

struct DebugTraceInjectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            DebugManualTraceInjectionView()
        }
    }
}

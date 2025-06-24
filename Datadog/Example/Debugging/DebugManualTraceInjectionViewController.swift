/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogTrace
import DatadogInternal

@available(iOS 14, *)
internal class DebugManualTraceInjectionViewController: UIHostingController<DebugManualTraceInjectionView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: DebugManualTraceInjectionView())
    }
}

private var currentSession: URLSession? = nil

extension TraceContextInjection {
    func toString() -> String {
        switch self {
        case .all:
            return "All"
        case .sampled:
            return "Sampled"
        }
    }
}

@available(iOS 14.0, *)
internal struct DebugManualTraceInjectionView: View {
    enum TraceHeaderType: String, CaseIterable, Identifiable {
        case datadog = "Datadog"
        case w3c = "W3C"
        case b3Single = "B3-Single"
        case b3Multiple = "B3-Multiple"
        
        var id: String { rawValue }
    }

    @State private var spanName = "network request"
    @State private var requestURL = "https://httpbin.org/get"
    @State private var selectedTraceHeaderTypes: Set<TraceHeaderType> = [.datadog, .w3c]
    @State private var selectedTraceContextInjection: TraceContextInjection = .sampled
    @State private var isRequestPending = false

    private let session: URLSession = URLSession(
        configuration: .ephemeral,
        delegate: DummySessionDataDelegate(),
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
                Picker("Trace context injection:", selection: $selectedTraceContextInjection) {
                    ForEach(TraceContextInjection.allCases, id: \.self) { headerType in
                        Text(headerType.toString())
                    }
                }
                .pickerStyle(.inline)
                MultiSelector(
                    label: Text("Trace header type:"),
                    options: TraceHeaderType.allCases,
                    optionToString: { $0.rawValue },
                    selected: $selectedTraceHeaderTypes
                )
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
        request.httpMethod = "GET"

        let span = Tracer.shared().startRootSpan(operationName: spanName)

        for selectedTraceHeaderType in selectedTraceHeaderTypes {
            switch selectedTraceHeaderType {
            case .datadog:
                let writer = HTTPHeadersWriter(
                    traceContextInjection: selectedTraceContextInjection
                )
                Tracer.shared().inject(spanContext: span.context, writer: writer)
                writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            case .w3c:
                let writer = W3CHTTPHeadersWriter(
                    tracestate: [:],
                    traceContextInjection: selectedTraceContextInjection
                )
                Tracer.shared().inject(spanContext: span.context, writer: writer)
                writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            case .b3Single:
                let writer = B3HTTPHeadersWriter(
                    injectEncoding: .single,
                    traceContextInjection: selectedTraceContextInjection
                )
                Tracer.shared().inject(spanContext: span.context, writer: writer)
                writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            case .b3Multiple:
                let writer = B3HTTPHeadersWriter(
                    injectEncoding: .multiple,
                    traceContextInjection: selectedTraceContextInjection
                )
                Tracer.shared().inject(spanContext: span.context, writer: writer)
                writer.traceHeaderFields.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            }
        }

        send(request: request) {
            span.finish()
            print("✅ Request sent to \(requestURL)")
        }
    }

    private func send(request: URLRequest, completion: @escaping () -> Void) {
        isRequestPending = true
        let task = session.dataTask(with: request) { data, response, _ in
            let httpResponse = response as! HTTPURLResponse
            print("🚀 Request completed with status code: \(httpResponse.statusCode)")

            // pretty print response
            if let data = data {
                let json = try? JSONSerialization.jsonObject(with: data, options: [])
                if let json = json {
                    print("🚀 Response: \(json)")
                }
            }
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

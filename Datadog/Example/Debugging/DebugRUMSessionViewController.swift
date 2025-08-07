/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import DatadogRUM
import DatadogTrace

@available(iOS 13, *)
internal class DebugRUMSessionViewController: UIHostingController<DebugRUMSessionView> {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder, rootView: DebugRUMSessionView())
    }
}

private enum SessionItemType {
    case view
    case resource
    case action
    case error
}

@available(iOS 13.0, *)
private class DebugRUMSessionViewModel: ObservableObject {
    struct SessionItem: Identifiable {
        let label: String
        let type: SessionItemType
        var isPending: Bool
        var stopAction: (() -> Void)?

        var id: UUID = UUID()
    }

    @Published var sessionItems: [SessionItem] = [] {
        didSet { updateSessionID() }
    }
    @Published var sessionID: String = ""

    @Published var viewKey: String = ""
    @Published var actionName: String = ""
    @Published var errorMessage: String = ""
    @Published var resourceKey: String = ""

    @Published var logMessage: String = ""
    @Published var spanOperationName: String = ""
    @Published var instrumentedRequestURL: String = "https://api.shopist.io/checkout.json"

    var urlSessions: [URLSession] = []

    init() {
        updateSessionID()
    }

    func startView() {
        guard !viewKey.isEmpty else {
            return
        }

        let key = viewKey
        RUMMonitor.shared().startView(key: key)

        sessionItems.append(
            SessionItem(
                label: key,
                type: .view,
                isPending: true,
                stopAction: { [weak self] in
                    self?.modifySessionItem(type: .view, label: key) { mutableSessionItem in
                        mutableSessionItem.isPending = false
                        mutableSessionItem.stopAction = nil
                        RUMMonitor.shared().stopView(key: key)
                    }
                }
            )
        )

        self.viewKey = ""
    }

    func addAction() {
        guard !actionName.isEmpty else {
            return
        }

        RUMMonitor.shared().addAction(type: .custom, name: actionName)
        sessionItems.append(
            SessionItem(label: actionName, type: .action, isPending: false, stopAction: nil)
        )

        self.actionName = ""
    }

    func addError() {
        guard !errorMessage.isEmpty else {
            return
        }

        RUMMonitor.shared().addError(message: errorMessage)
        sessionItems.append(
            SessionItem(label: errorMessage, type: .error, isPending: false, stopAction: nil)
        )

        self.errorMessage = ""
    }

    func startResource() {
        guard !resourceKey.isEmpty else {
            return
        }

        let key = self.resourceKey
        RUMMonitor.shared().startResource(resourceKey: key, url: mockURL())
        sessionItems.append(
            SessionItem(
                label: key,
                type: .resource,
                isPending: true,
                stopAction: { [weak self] in
                    self?.modifySessionItem(type: .resource, label: key) { mutableSessionItem in
                        mutableSessionItem.isPending = false
                        mutableSessionItem.stopAction = nil
                        RUMMonitor.shared().stopResource(resourceKey: key, statusCode: nil, kind: .other)
                    }
                }
            )
        )

        self.resourceKey = ""
    }

    func sendLog() {
        logger.debug(logMessage)
        logMessage = ""
    }

    func sendSpan() {
        let span = Tracer.shared().startRootSpan(operationName: spanOperationName, tags: [:])
        Thread.sleep(forTimeInterval: 0.1)
        span.finish()
        spanOperationName = ""
    }

    func sendPOSTRequest() {
        guard let url = URL(string: instrumentedRequestURL) else {
            print("🔥 POST Request not sent - invalid url: \(instrumentedRequestURL)")
            return
        }

        let delegate = DummySessionDataDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let task = session.dataTask(with: request) { _, _, error in
            if let error = error {
                print("🌍🔥 POST \(url) completed with network error: \(error)")
            } else {
                print("🌍 POST \(url) sent successfully")
            }
        }
        task.resume()

        urlSessions.append(session) // keep session
    }

    func stopSession() {
        RUMMonitor.shared().stopSession()
        sessionItems = []
    }

    // MARK: - Private

    private func modifySessionItem(type: SessionItemType, label: String, change: (inout SessionItem) -> Void) {
        sessionItems = sessionItems.map { item in
            var item = item
            if item.type == type, item.label == label {
                change(&item)
            }
            return item
        }
    }

    private func mockURL() -> URL {
        return URL(string: "https://foo.com/\(UUID().uuidString)")!
    }

    private func updateSessionID() {
        RUMMonitor.shared().currentSessionID { [weak self] id in
            DispatchQueue.main.async {
                self?.sessionID = id ?? "-"
            }
        }
    }
}

@available(iOS 13.0, *)
internal struct DebugRUMSessionView: View {
    @ObservedObject private var viewModel = DebugRUMSessionViewModel()

    var body: some View {
        VStack() {
            Group {
                Text("RUM Session")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.bold))
                Text("Debug RUM Session by creating events manually:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.light))
                HStack {
                    FormItemView(
                        title: "RUM View", placeholder: "view key", accent: .rumViewColor, value: $viewModel.viewKey
                    )
                    Button("START") { viewModel.startView() }
                }
                HStack {
                    FormItemView(
                        title: "RUM Action", placeholder: "name", accent: .rumActionColor, value: $viewModel.actionName
                    )
                    Button("ADD") { viewModel.addAction() }
                }
                HStack {
                    FormItemView(
                        title: "RUM Error", placeholder: "message", accent: .rumErrorColor, value: $viewModel.errorMessage
                    )
                    Button("ADD") { viewModel.addError() }
                }
                HStack {
                    FormItemView(
                        title: "RUM Resource", placeholder: "key", accent: .rumResourceColor, value: $viewModel.resourceKey
                    )
                    Button("START") { viewModel.startResource() }
                }
                HStack {
                    Button("STOP SESSION") { viewModel.stopSession() }
                    Spacer()
                }
                Divider()
            }
            Group {
                Text("Bundling Logs and Spans")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.bold))
                Text("Debug bundling Logs and Spans with RUM Session by sending them manually while the session is active.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.light))
                HStack {
                    FormItemView(
                        title: "Log", placeholder: "log message", accent: .gray, value: $viewModel.logMessage
                    )
                    Button("Send") { viewModel.sendLog() }
                }
                HStack {
                    FormItemView(
                        title: "Span", placeholder: "span name", accent: .gray, value: $viewModel.spanOperationName
                    )
                    Button("Send") { viewModel.sendSpan() }
                }
                Text("Send 1st party request with instrumented URLSession:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.light))
                HStack {
                    FormItemView(
                        title: "POST Request", placeholder: "request url", accent: .gray, value: $viewModel.instrumentedRequestURL
                    )
                    Button("Send") { viewModel.sendPOSTRequest() }
                }
                Divider()
            }
            Group {
                Text("Current RUM Session")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.bold))
                Text("UUID: \(viewModel.sessionID)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.caption.weight(.ultraLight))
                List(viewModel.sessionItems) { sessionItem in
                    SessionItemView(item: sessionItem)
                        .listRowInsets(EdgeInsets())
                        .padding(4)
                }
                .listStyle(PlainListStyle())
            }
        }
        .buttonStyle(DatadogButtonStyle())
        .padding()
    }
}

@available(iOS 13.0, *)
private struct FormItemView: View {
    let title: String
    let placeholder: String
    let accent: Color

    @Binding var value: String

    var body: some View {
        HStack {
            Text(title)
                .bold()
                .font(.system(size: 10))
                .padding(4)
                .background(accent)
                .foregroundColor(Color.white)
                .cornerRadius(4)
            TextField(placeholder, text: $value)
                .font(.system(size: 12))
                .padding(4)
                .background(Color(UIColor.secondarySystemFill))
                .cornerRadius(4)
        }
        .padding(4)
        .background(Color(UIColor.systemFill))
        .foregroundColor(Color.secondary)
        .cornerRadius(4)
    }
}

@available(iOS 13.0, *)
private struct SessionItemView: View {
    let item: DebugRUMSessionViewModel.SessionItem

    var body: some View {
        HStack() {
            HStack() {
                Text(label(for: item.type))
                    .bold()
                    .font(.system(size: 10))
                    .padding(4)
                    .background(color(for: item.type))
                    .foregroundColor(Color.white)
                    .cornerRadius(4)
                Text(item.label)
                    .bold()
                    .font(.system(size: 14))
                Spacer()
            }
            .padding(4)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemFill))
            .foregroundColor(Color.secondary)
            .cornerRadius(4)

            if item.isPending {
                Button("STOP") { item.stopAction?() }
            }
        }
    }

    private func color(for sessionItemType: SessionItemType) -> Color {
        switch sessionItemType {
        case .view:     return .rumViewColor
        case .resource: return .rumResourceColor
        case .action:   return .rumActionColor
        case .error:    return .rumErrorColor
        }
    }

    private func label(for sessionItemType: SessionItemType) -> String {
        switch sessionItemType {
        case .view:     return "RUM View"
        case .resource: return "RUM Resource"
        case .action:   return "RUM Action"
        case .error:    return "RUM Error"
        }
    }
}

// MARK - Preview

@available(iOS 13.0, *)
struct DebugRUMSessionViewController_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DebugRUMSessionView()
                .previewLayout(.fixed(width: 400, height: 500))
                .preferredColorScheme(.light)
            DebugRUMSessionView()
                .previewLayout(.fixed(width: 400, height: 500))
                .preferredColorScheme(.dark)
        }
    }
}

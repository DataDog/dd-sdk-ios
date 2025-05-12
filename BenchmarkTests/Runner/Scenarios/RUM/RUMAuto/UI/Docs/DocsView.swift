/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI
import WebKit

struct DocsView: UIViewRepresentable {
    let url: URL = .init(string: "https://rickandmortyapi.com/documentation")!

    func makeUIView(context _: Context) -> some UIView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateUIView(_: UIViewType, context _: Context) {}
}

#Preview {
    DocsView()
}

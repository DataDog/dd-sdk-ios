//
//  WebView.swift
//  SwiftUICatalog
//
//  Created by Barbara Rodeker on 2022-05-21.
//
// MIT License
//
// Copyright (c) 2024 Barbara Rodeker
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import SwiftUI
import WebKit

struct WebView: UIViewRepresentable, Identifiable {
    
    var id: String {
        return url.absoluteString
    }
    /// url to load
    private let url: URL
    /// delegate to restrict the navigation to only the specified ulr
    private let delegate: WKWebViewDelegate
    
    init(url: URL) {
        self.url = url
        self.delegate = WKWebViewDelegate(url: url)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = delegate
        return view
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.navigationDelegate = delegate
        webView.load(request)
    }
    
}

final class WKWebViewDelegate: NSObject, WKNavigationDelegate {
    private let url: URL
    
    init(url: URL) {
        self.url = url
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let urlToOpen = navigationAction.request.url,
              urlToOpen.absoluteString == url.absoluteString else {
            return .cancel
        }
        return .allow
    }
}

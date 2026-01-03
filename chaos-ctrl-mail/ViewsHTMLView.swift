//
//  HTMLView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI
import WebKit

struct HTMLView: UIViewRepresentable {
    let htmlContent: String
    var onHeightChange: ((CGFloat) -> Void)? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Disable scrolling since it's inside a ScrollView; size to content instead
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Wrap HTML in a basic HTML structure if needed
        let html = wrapHTML(htmlContent)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        private let onHeightChange: ((CGFloat) -> Void)?
        
        init(onHeightChange: ((CGFloat) -> Void)?) {
            self.onHeightChange = onHeightChange
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Measure content height after load
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { result, _ in
                if let height = result as? CGFloat, height > 0 {
                    DispatchQueue.main.async {
                        self.onHeightChange?(height)
                    }
                }
            }
        }
    }
    
    private func wrapHTML(_ content: String) -> String {
        // If content already has HTML structure, return as-is
        if content.contains("<html") || content.contains("<HTML") || content.contains("<!DOCTYPE") {
            return content
        }
        
        // Otherwise, wrap in basic HTML structure
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
                    font-size: 16px;
                    line-height: 1.5;
                    color: #000;
                    padding: 16px;
                    margin: 0;
                    word-wrap: break-word;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}


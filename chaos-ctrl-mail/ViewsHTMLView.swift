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
        webView.isOpaque = true
        webView.backgroundColor = .white
        webView.scrollView.backgroundColor = .white
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
        // If content already has HTML structure, return as-is (preserves all original styling)
        if content.contains("<html") || content.contains("<HTML") || content.contains("<!DOCTYPE") {
            return content
        }
        
        // Otherwise, wrap in minimal HTML structure that preserves email styling
        // Use minimal default styles that don't override the email's CSS
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                /* Minimal default styles that don't override email styling */
                body {
                    margin: 0;
                    padding: 16px;
                    word-wrap: break-word;
                    /* Only set background if email doesn't specify one */
                    background-color: #fff;
                    /* Ensure content doesn't overflow screen width */
                    max-width: 100%;
                    overflow-x: hidden;
                }
                /* Ensure images scale properly but preserve email styling */
                img {
                    max-width: 100%;
                    height: auto;
                }
                /* Make tables responsive */
                table {
                    max-width: 100%;
                    width: 100% !important;
                    table-layout: auto;
                }
                /* Ensure table cells wrap */
                td, th {
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                /* Make divs and other block elements responsive */
                div, p, span {
                    max-width: 100%;
                    box-sizing: border-box;
                }
                /* Preserve email's font, color, and other styling by not setting defaults */
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
    }
}


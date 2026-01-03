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
        
        // Store the coordinator's htmlContent to track changes
        context.coordinator.lastHTMLContent = htmlContent
        
        // Load initial content
        let html = wrapHTML(htmlContent)
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Only reload if the content has actually changed
        if context.coordinator.lastHTMLContent != htmlContent {
            context.coordinator.lastHTMLContent = htmlContent
            let html = wrapHTML(htmlContent)
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        private let onHeightChange: ((CGFloat) -> Void)?
        var lastHTMLContent: String = ""
        
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
        // If content already has HTML structure, inject responsive CSS
        if content.contains("<html") || content.contains("<HTML") || content.contains("<!DOCTYPE") {
            return injectResponsiveCSS(content)
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
    
    private func injectResponsiveCSS(_ html: String) -> String {
        // Inject responsive CSS and viewport meta tag into existing HTML
        var modified = html
        
        // Ensure viewport meta tag is present
        let viewportMeta = "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no\">"
        if !modified.lowercased().contains("viewport") {
            // Insert viewport meta after <head> or <HTML>
            if let headRange = modified.range(of: "<head>", options: .caseInsensitive) {
                modified.insert(contentsOf: "\n    \(viewportMeta)\n", at: modified.index(after: headRange.upperBound))
            } else if let htmlRange = modified.range(of: "<html", options: .caseInsensitive) {
                // If no <head>, insert before first tag after <html>
                if let closeRange = modified.range(of: ">", range: htmlRange.upperBound..<modified.endIndex) {
                    modified.insert(contentsOf: "\n<head>\n    \(viewportMeta)\n</head>", at: modified.index(after: closeRange.upperBound))
                }
            }
        }
        
        // Inject responsive CSS into <head> or before </head>
        let responsiveCSS = """
        <style>
            /* Responsive styles to prevent content overflow */
            body {
                max-width: 100% !important;
                overflow-x: hidden !important;
                word-wrap: break-word !important;
            }
            table {
                max-width: 100% !important;
                width: 100% !important;
                table-layout: auto !important;
            }
            td, th {
                word-wrap: break-word !important;
                overflow-wrap: break-word !important;
            }
            div, p, span, section, article {
                max-width: 100% !important;
                box-sizing: border-box !important;
            }
            img {
                max-width: 100% !important;
                height: auto !important;
            }
        </style>
        """
        
        // Insert CSS before </head> if head exists, otherwise before </html> or at end
        if let headCloseRange = modified.range(of: "</head>", options: .caseInsensitive) {
            modified.insert(contentsOf: "\n    \(responsiveCSS)\n    ", at: headCloseRange.lowerBound)
        } else if let htmlCloseRange = modified.range(of: "</html>", options: .caseInsensitive) {
            // Insert head with CSS before </html>
            modified.insert(contentsOf: "<head>\n    \(viewportMeta)\n    \(responsiveCSS)\n</head>\n", at: htmlCloseRange.lowerBound)
        } else {
            // No closing tags, append to end (unlikely but handle it)
            modified = modified + "\n<head>\n    \(viewportMeta)\n    \(responsiveCSS)\n</head>\n"
        }
        
        return modified
    }
}


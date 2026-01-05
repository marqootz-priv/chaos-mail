//
//  FaviconValidator.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/4/26.
//

import Foundation

/// Validates favicon URLs to detect generic placeholders
actor FaviconValidator {
    static let shared = FaviconValidator()
    
    private var cache: [URL: Bool] = [:]
    
    private init() {}
    
    /// Checks if a favicon URL is likely to return a generic placeholder
    /// Returns true if the URL appears valid, false if it's likely generic
    func isValidFaviconURL(_ url: URL) async -> Bool {
        // Check cache first
        if let cached = cache[url] {
            print("FAVICON: FaviconValidator - Using cached result: \(cached ? "VALID" : "INVALID") for URL: \(url.absoluteString)")
            return cached
        }
        
        print("FAVICON: FaviconValidator - Validating URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // Only fetch headers, not body
        request.timeoutInterval = 2.0 // Give it a bit more time
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData // Don't use cache for validation
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  let finalURL = httpResponse.url else {
                print("FAVICON: FaviconValidator - No valid response")
                cache[url] = true
                return true
            }
                
                let finalURLString = finalURL.absoluteString.lowercased()
                print("FAVICON: FaviconValidator - Final URL after redirect: \(finalURLString)")
                print("FAVICON: FaviconValidator - Status code: \(httpResponse.statusCode)")
                
                // Key insight: Google's favicon API has two redirect patterns:
                // 1. Real favicon: https://t0.gstatic.com/favicons?domain=... (OR any domain's real icon)
                // 2. Generic placeholder: https://t3.gstatic.com/faviconV2?...&fallback_opts=...
                
                // The DEFINITIVE check: Does it contain fallback_opts?
                // This is the ONLY reliable indicator of a generic placeholder
                let hasGenericFallback = finalURLString.contains("fallback_opts")
                
                let isValid = !hasGenericFallback
                
                print("FAVICON: FaviconValidator - Has fallback_opts: \(hasGenericFallback), Result: \(isValid ? "VALID" : "INVALID (generic placeholder)")")
                
                // Cache result
                cache[url] = isValid
                
                return isValid
        } catch {
            print("FAVICON: FaviconValidator - Network error: \(error.localizedDescription), assuming valid")
            // Network error - assume valid (don't block favicons on network issues)
            cache[url] = true
            return true
        }
        
        print("FAVICON: FaviconValidator - Could not determine validity, assuming valid")
        // Default to valid if we can't determine
        cache[url] = true
        return true
    }
    
    /// Clear the validation cache
    func clearCache() {
        cache.removeAll()
    }
}

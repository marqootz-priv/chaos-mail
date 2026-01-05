//
//  CompanyAvatarView.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import SwiftUI

struct CompanyAvatarView: View {
    let email: String
    let size: CGFloat
    
    private func avatarColor() -> Color {
        let hash = abs(email.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.8)
    }
    
    private func avatarText() -> String {
        // Extract domain name for company emails
        if email.contains("@") {
            if let atIndex = email.firstIndex(of: "@") {
                let domain = String(email[email.index(after: atIndex)...])
                let companyName = domain.components(separatedBy: ".").first ?? domain
                return String(companyName.prefix(1).uppercased())
            }
        }
        
        // Personal email - use first letter of name part
        let namePart = email.components(separatedBy: "@").first ?? email
        return String(namePart.prefix(1).uppercased())
    }
    
    private func extractDomain(from email: String) -> String? {
        guard email.contains("@") else { return nil }
        if let atIndex = email.firstIndex(of: "@") {
            var domain = String(email[email.index(after: atIndex)...])
            
            // Sanitize domain: remove common prefixes like "mail.", "www."
            domain = domain.trimmingCharacters(in: .whitespaces)
            if domain.hasPrefix("mail.") {
                domain = String(domain.dropFirst(5))
            }
            if domain.hasPrefix("www.") {
                domain = String(domain.dropFirst(4))
            }
            return domain
        }
        return nil
    }
    
    private func normalizeToRootDomain(_ domain: String) -> String {
        var cleaned = domain.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Remove common prefixes
        let prefixesToRemove = ["mail.", "www.", "www1.", "www2.", "webmail.", "email."]
        for prefix in prefixesToRemove {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count))
            }
        }
        
        // Special handling for major email providers
        if cleaned.contains("google.com") { return "google.com" }
        if cleaned == "gmail.com" { return "gmail.com" }
        if cleaned.contains("icloud.com") || cleaned.contains("me.com") || cleaned.contains("mac.com") { return "apple.com" }
        if cleaned.contains("outlook.com") || cleaned.contains("live.com") || cleaned.contains("hotmail.com") || cleaned.contains("office365.com") { return "microsoft.com" }
        if cleaned.contains("yahoo.com") || cleaned.contains("yahoo.co.uk") || cleaned.contains("yahoo.co.jp") { return "yahoo.com" }
        
        // Country-code second-level domains (ccSLDs) that should keep three parts
        let ccSLDs: Set<String> = [
            "edu.in", "co.in", "gov.in", "ac.in", "org.in",
            "co.uk", "ac.uk", "gov.uk", "org.uk",
            "co.jp", "ac.jp", "go.jp", "or.jp",
            "co.nz", "ac.nz", "gov.nz", "org.nz",
            "com.au", "co.au", "gov.au", "ac.au", "org.au",
            "com.br", "co.br", "gov.br", "org.br", "ac.br",
            "com.mx", "co.mx", "gov.mx", "org.mx",
            "com.ar", "co.ar", "gov.ar", "org.ar",
            "co.za", "ac.za", "gov.za", "org.za",
            "co.kr", "ac.kr", "go.kr", "or.kr",
            "co.id", "ac.id", "go.id",
            "co.th", "ac.th", "go.th",
            "co.ve", "ac.ve", "gov.ve",
            "co.tz", "ac.tz", "go.tz"
        ]
        
        let parts = cleaned.components(separatedBy: ".")
        
        // If domain ends with a ccSLD and has at least 3 parts, keep the last 3 parts
        if parts.count >= 3 {
            let lastTwo = parts.suffix(2).joined(separator: ".")
            if ccSLDs.contains(lastTwo) {
                return parts.suffix(3).joined(separator: ".")
            }
        }
        
        // Single part or two parts: return as-is
        if parts.count <= 2 {
            return cleaned
        }
        
        // Default: take last two parts
        return parts.suffix(2).joined(separator: ".")
    }
    
    
private func faviconURL(for domain: String) -> URL? {
        let rootDomain = normalizeToRootDomain(domain)
        
        // Google's Favicon API (fastest, most reliable)
        if let encodedDomain = rootDomain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            let faviconSize = min(max(Int(size), 16), 512)
            let urlString = "https://www.google.com/s2/favicons?sz=\(faviconSize)&domain=\(encodedDomain)"
            if let url = URL(string: urlString) {
                return url
            }
        }
        
        return nil
    }
    
    var body: some View {
        Group {
            if let domain = extractDomain(from: email) {
                if let url = faviconURL(for: domain) {
                    // Company email - try to load favicon with validation
                    FaviconImageWithValidation(
                        url: url,
                        size: size,
                        avatarColor: avatarColor(),
                        avatarText: avatarText()
                    )
                } else {
                    // No URL - use letter initial
                    letterInitialView()
                }
            } else {
                // Personal email or no domain - use letter initial
                letterInitialView()
            }
        }
        .onAppear {
            if let domain = extractDomain(from: email) {
                if let url = faviconURL(for: domain) {
                    print("FAVICON: CompanyAvatarView - Attempting to load favicon for domain: \(domain), URL: \(url.absoluteString)")
                } else {
                    print("FAVICON: CompanyAvatarView - No favicon URL generated for domain: \(domain)")
                }
            } else {
                print("FAVICON: CompanyAvatarView - No domain extracted from email: \(email)")
            }
        }
    }
    
    private func letterInitialView() -> some View {
        Circle()
            .fill(avatarColor())
            .frame(width: size, height: size)
            .overlay {
                Text(avatarText())
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .font(.system(size: size * 0.4))
            }
    }
}

/// Wrapper view that validates favicon URLs before displaying them
struct FaviconImageWithValidation: View {
    let url: URL
    let size: CGFloat
    let avatarColor: Color
    let avatarText: String
    
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                    }
            case .empty:
                // Loading state - show placeholder
                Circle()
                    .fill(avatarColor)
                    .frame(width: size, height: size)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            case .failure:
                // Failed to load favicon - fallback to letter
                letterInitialView()
            @unknown default:
                // Fallback
                letterInitialView()
            }
        }
    }
    
    private func letterInitialView() -> some View {
        Circle()
            .fill(avatarColor)
            .frame(width: size, height: size)
            .overlay {
                Text(avatarText)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
                    .font(.system(size: size * 0.4))
            }
    }
}

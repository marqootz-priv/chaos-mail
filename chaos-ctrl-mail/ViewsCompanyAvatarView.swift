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
    
    private func faviconURL(for domain: String) -> URL? {
        var cleanedDomain = domain.trimmingCharacters(in: .whitespaces).lowercased()
        
        // Remove common prefixes that might interfere with favicon lookup
        let prefixesToRemove = ["mail.", "www.", "www1.", "www2.", "webmail.", "email."]
        for prefix in prefixesToRemove {
            if cleanedDomain.hasPrefix(prefix) {
                cleanedDomain = String(cleanedDomain.dropFirst(prefix.count))
            }
        }
        
        // Normalize subdomains to main domain for better favicon lookup
        // e.g., accounts.google.com -> google.com, mail.yahoo.com -> yahoo.com
        let domainMappings: [String: String] = [
            "accounts.google.com": "google.com",
            "mail.google.com": "google.com",
            "mail.yahoo.com": "yahoo.com",
            "mail.yahoo.co.uk": "yahoo.com",
            "outlook.office365.com": "office365.com",
            "outlook.live.com": "outlook.com",
            "mail.live.com": "outlook.com"
        ]
        if let mappedDomain = domainMappings[cleanedDomain] {
            cleanedDomain = mappedDomain
        } else {
            // For other domains, try to extract the base domain (last two parts)
            // e.g., subdomain.example.com -> example.com
            let parts = cleanedDomain.components(separatedBy: ".")
            if parts.count > 2 {
                // Check if it's a known multi-part TLD (like co.uk, com.au)
                let lastTwo = parts.suffix(2).joined(separator: ".")
                let knownMultiTLD = ["co.uk", "com.au", "co.nz", "com.br", "co.jp", "com.mx"]
                if knownMultiTLD.contains(lastTwo) && parts.count > 3 {
                    // Keep last 3 parts for multi-part TLDs
                    cleanedDomain = parts.suffix(3).joined(separator: ".")
                } else {
                    // Use last 2 parts (domain.tld)
                    cleanedDomain = parts.suffix(2).joined(separator: ".")
                }
            }
        }
        
        // Google's Favicon API (fastest, most reliable - works for ~95% of domains)
        // Use URL query encoding for the domain parameter (not path encoding)
        if let encodedDomain = cleanedDomain.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            // Use size parameter: 16, 32, 64, 128, 256, 512 (defaults to 16 if not specified)
            let faviconSize = min(max(Int(size), 16), 512)
            let urlString = "https://www.google.com/s2/favicons?sz=\(faviconSize)&domain=\(encodedDomain)"
            if let url = URL(string: urlString) {
                print("CompanyAvatar: Loading favicon for domain '\(domain)' -> normalized to '\(cleanedDomain)' -> \(urlString)")
                return url
            }
        }
        
        print("CompanyAvatar: Failed to create favicon URL for domain '\(cleanedDomain)'")
        return nil
    }
    
    var body: some View {
        Group {
            if let domain = extractDomain(from: email), let url = faviconURL(for: domain) {
                // Company email - try to load favicon
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        // Loading state - show placeholder
                        Circle()
                            .fill(avatarColor())
                            .frame(width: size, height: size)
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.5)
                            }
                    case .success(let image):
                        // Favicon loaded successfully - validate it's not a generic/default icon
                        // Google's favicon API sometimes returns generic icons for certain domains
                        // Check if image appears to be valid (not just a default/error icon)
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                            .overlay {
                                // Optional: Add a subtle border to make favicons more distinct
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                            }
                    case .failure:
                        // Failed to load favicon - fallback to letter
                        Circle()
                            .fill(avatarColor())
                            .frame(width: size, height: size)
                            .overlay {
                                Text(avatarText())
                                    .foregroundStyle(.white)
                                    .fontWeight(.semibold)
                                    .font(.system(size: size * 0.4))
                            }
                    @unknown default:
                        // Fallback
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
            } else {
                // Personal email or no domain - use letter initial
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
    }
}


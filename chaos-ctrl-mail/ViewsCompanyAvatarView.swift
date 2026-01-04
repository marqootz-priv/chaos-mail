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
        // Google: All Google subdomains use google.com favicon
        if cleaned.contains("google.com") {
            return "google.com"
        }
        
        // Gmail: Use gmail.com (but Google favicon API will handle it)
        if cleaned == "gmail.com" {
            return "gmail.com"
        }
        
        // Apple: iCloud and me.com use apple.com
        if cleaned.contains("icloud.com") || cleaned.contains("me.com") || cleaned.contains("mac.com") {
            return "apple.com"
        }
        
        // Microsoft: Outlook and Live use microsoft.com
        if cleaned.contains("outlook.com") || cleaned.contains("live.com") || cleaned.contains("hotmail.com") || cleaned.contains("office365.com") {
            return "microsoft.com"
        }
        
        // Yahoo: All Yahoo subdomains use yahoo.com
        if cleaned.contains("yahoo.com") || cleaned.contains("yahoo.co.uk") || cleaned.contains("yahoo.co.jp") {
            return "yahoo.com"
        }
        
        // For other domains, extract root domain (last two parts)
        // e.g., accounts.example.com -> example.com
        let parts = cleaned.components(separatedBy: ".")
        
        // Single part or two parts: return as-is
        if parts.count <= 2 {
            return cleaned
        }
        
        // Three or more parts: take last two parts (domain.tld)
        // This handles: subdomain.example.com -> example.com
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
                    // No URL - use letter initial
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

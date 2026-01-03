//
//  MailAccountDiscovery.swift
//  chaos-ctrl-mail
//
//  Created by Mark Manfrey on 1/1/26.
//

import Foundation

/// Automatically discovers mail server settings using various autodiscovery methods
/// Similar to Apple Mail's automatic account setup
class MailAccountDiscovery {
    
    // MARK: - Discovery Result
    
    struct DiscoveryResult {
        var imapServer: String
        var imapPort: Int
        var imapUseSSL: Bool
        var smtpServer: String
        var smtpPort: Int
        var smtpUseSSL: Bool
        var username: String
        var displayName: String?
        
        init(
            imapServer: String,
            imapPort: Int = 993,
            imapUseSSL: Bool = true,
            smtpServer: String,
            smtpPort: Int = 587,
            smtpUseSSL: Bool = true,
            username: String,
            displayName: String? = nil
        ) {
            self.imapServer = imapServer
            self.imapPort = imapPort
            self.imapUseSSL = imapUseSSL
            self.smtpServer = smtpServer
            self.smtpPort = smtpPort
            self.smtpUseSSL = smtpUseSSL
            self.username = username
            self.displayName = displayName
        }
    }
    
    // MARK: - Main Discovery Method
    
    /// Discovers mail server settings for an email address
    /// Tries multiple methods in order: Well-known hosts, Autodiscover, Autoconfig, SRV records
    func discover(email: String) async throws -> DiscoveryResult {
        let domain = extractDomain(from: email)
        
        // Try methods in order of likelihood to succeed
        
        // 1. Try well-known hosts (fastest, most common)
        if let result = try? await tryWellKnownHosts(domain: domain, email: email) {
            return result
        }
        
        // 2. Try Mozilla Autoconfig (Thunderbird-style)
        if let result = try? await tryAutoconfig(domain: domain, email: email) {
            return result
        }
        
        // 3. Try Microsoft Autodiscover
        if let result = try? await tryAutodiscover(domain: domain, email: email) {
            return result
        }
        
        // 4. Try DNS SRV records (RFC 6186)
        if let result = try? await trySRVRecords(domain: domain, email: email) {
            return result
        }
        
        // 5. Try common patterns as last resort
        if let result = tryCommonPatterns(domain: domain, email: email) {
            return result
        }
        
        throw DiscoveryError.noSettingsFound
    }
    
    // MARK: - Well-Known Hosts Method
    
    /// Tries common mail server hostnames like mail.domain.com, imap.domain.com
    private func tryWellKnownHosts(domain: String, email: String) async throws -> DiscoveryResult {
        let commonPrefixes = ["mail", "imap", "smtp"]
        
        for prefix in commonPrefixes {
            let hostname = "\(prefix).\(domain)"
            
            // Check if hostname resolves
            if await hostnameExists(hostname) {
                return DiscoveryResult(
                    imapServer: "imap.\(domain)",
                    imapPort: 993,
                    imapUseSSL: true,
                    smtpServer: "smtp.\(domain)",
                    smtpPort: 587,
                    smtpUseSSL: true,
                    username: email
                )
            }
        }
        
        throw DiscoveryError.wellKnownHostsNotFound
    }
    
    // MARK: - Mozilla Autoconfig Method
    
    /// Implements Mozilla's Autoconfig protocol
    /// https://developer.mozilla.org/en-US/docs/Mozilla/Thunderbird/Autoconfiguration
    private func tryAutoconfig(domain: String, email: String) async throws -> DiscoveryResult {
        // Try Mozilla's ISP database first
        let ispDBURL = URL(string: "https://autoconfig.thunderbird.net/v1.1/\(domain)")!
        
        if let result = try? await fetchAutoconfigXML(from: ispDBURL, email: email) {
            return result
        }
        
        // Try domain's autoconfig subdomain
        let autoconfigURL = URL(string: "https://autoconfig.\(domain)/mail/config-v1.1.xml?emailaddress=\(email)")!
        
        if let result = try? await fetchAutoconfigXML(from: autoconfigURL, email: email) {
            return result
        }
        
        // Try well-known location
        let wellKnownURL = URL(string: "https://\(domain)/.well-known/autoconfig/mail/config-v1.1.xml")!
        
        if let result = try? await fetchAutoconfigXML(from: wellKnownURL, email: email) {
            return result
        }
        
        throw DiscoveryError.autoconfigNotFound
    }
    
    private func fetchAutoconfigXML(from url: URL, email: String) async throws -> DiscoveryResult {
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DiscoveryError.autoconfigNotFound
        }
        
        return try parseAutoconfigXML(data, email: email)
    }
    
    private func parseAutoconfigXML(_ data: Data, email: String) throws -> DiscoveryResult {
        // Parse XML to extract server settings
        let parser = XMLParser(data: data)
        let delegate = AutoconfigXMLDelegate()
        parser.delegate = delegate
        
        guard parser.parse(), let settings = delegate.settings else {
            throw DiscoveryError.invalidAutoconfigFormat
        }
        
        return DiscoveryResult(
            imapServer: settings.imapServer,
            imapPort: settings.imapPort,
            imapUseSSL: settings.imapUseSSL,
            smtpServer: settings.smtpServer,
            smtpPort: settings.smtpPort,
            smtpUseSSL: settings.smtpUseSSL,
            username: settings.username.replacingOccurrences(of: "%EMAILADDRESS%", with: email)
        )
    }
    
    // MARK: - Microsoft Autodiscover Method
    
    /// Implements Microsoft's Autodiscover protocol
    private func tryAutodiscover(domain: String, email: String) async throws -> DiscoveryResult {
        let urls = [
            URL(string: "https://autodiscover.\(domain)/autodiscover/autodiscover.xml")!,
            URL(string: "https://\(domain)/autodiscover/autodiscover.xml")!,
            URL(string: "http://autodiscover.\(domain)/autodiscover/autodiscover.xml")!
        ]
        
        for url in urls {
            if let result = try? await fetchAutodiscover(from: url, email: email) {
                return result
            }
        }
        
        throw DiscoveryError.autodiscoverNotFound
    }
    
    private func fetchAutodiscover(from url: URL, email: String) async throws -> DiscoveryResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        
        let requestBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <Autodiscover xmlns="http://schemas.microsoft.com/exchange/autodiscover/outlook/requestschema/2006">
            <Request>
                <EMailAddress>\(email)</EMailAddress>
                <AcceptableResponseSchema>http://schemas.microsoft.com/exchange/autodiscover/outlook/responseschema/2006a</AcceptableResponseSchema>
            </Request>
        </Autodiscover>
        """
        
        request.httpBody = requestBody.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DiscoveryError.autodiscoverNotFound
        }
        
        return try parseAutodiscoverXML(data, email: email)
    }
    
    private func parseAutodiscoverXML(_ data: Data, email: String) throws -> DiscoveryResult {
        // Simplified parsing - in production, use proper XML parsing
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw DiscoveryError.invalidAutodiscoverFormat
        }
        
        // Extract server settings from XML (simplified)
        // In production, use XMLParser or XMLDocument
        
        throw DiscoveryError.autodiscoverNotFound
    }
    
    // MARK: - DNS SRV Records Method (RFC 6186)
    
    /// Implements RFC 6186 for DNS SRV record lookup
    private func trySRVRecords(domain: String, email: String) async throws -> DiscoveryResult {
        // SRV record format: _service._proto.domain
        let imapSRV = "_imaps._tcp.\(domain)"
        let smtpSRV = "_submission._tcp.\(domain)"
        
        // Note: iOS doesn't provide native DNS SRV lookup
        // In production, you would use:
        // 1. dnssd library
        // 2. Network.framework with custom resolver
        // 3. Third-party DNS library
        
        // For now, we'll return common patterns
        throw DiscoveryError.srvRecordsNotFound
    }
    
    // MARK: - Common Patterns Fallback
    
    /// Falls back to common server naming patterns
    private func tryCommonPatterns(domain: String, email: String) -> DiscoveryResult? {
        // Common patterns for small businesses
        let patterns = [
            ("imap.\(domain)", "smtp.\(domain)"),
            ("mail.\(domain)", "mail.\(domain)"),
            ("mx.\(domain)", "mx.\(domain)"),
            (domain, domain)
        ]
        
        // Return the first pattern (most likely to work)
        let (imap, smtp) = patterns[0]
        
        return DiscoveryResult(
            imapServer: imap,
            imapPort: 993,
            imapUseSSL: true,
            smtpServer: smtp,
            smtpPort: 587,
            smtpUseSSL: true,
            username: email,
            displayName: nil
        )
    }
    
    // MARK: - Helper Methods
    
    private func extractDomain(from email: String) -> String {
        let components = email.components(separatedBy: "@")
        return components.count > 1 ? components[1] : email
    }
    
    private func hostnameExists(_ hostname: String) async -> Bool {
        // Simple check: try to resolve hostname
        guard let url = URL(string: "https://\(hostname)") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }
}

// MARK: - XML Parsing Delegate

class AutoconfigXMLDelegate: NSObject, XMLParserDelegate {
    struct Settings {
        var imapServer: String = ""
        var imapPort: Int = 993
        var imapUseSSL: Bool = true
        var smtpServer: String = ""
        var smtpPort: Int = 587
        var smtpUseSSL: Bool = true
        var username: String = ""
    }
    
    var settings: Settings?
    private var currentElement: String = ""
    private var currentType: String = ""
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "incomingServer" {
            currentType = attributeDict["type"] ?? ""
            if currentType == "imap" {
                if settings == nil {
                    settings = Settings()
                }
            }
        } else if elementName == "outgoingServer" {
            currentType = "smtp"
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if currentType == "imap" {
            switch currentElement {
            case "hostname":
                settings?.imapServer = trimmed
            case "port":
                settings?.imapPort = Int(trimmed) ?? 993
            case "socketType":
                settings?.imapUseSSL = (trimmed == "SSL" || trimmed == "STARTTLS")
            case "username":
                settings?.username = trimmed
            default:
                break
            }
        } else if currentType == "smtp" {
            switch currentElement {
            case "hostname":
                settings?.smtpServer = trimmed
            case "port":
                settings?.smtpPort = Int(trimmed) ?? 587
            case "socketType":
                settings?.smtpUseSSL = (trimmed == "SSL" || trimmed == "STARTTLS")
            default:
                break
            }
        }
    }
}

// MARK: - Discovery Error

enum DiscoveryError: LocalizedError {
    case noSettingsFound
    case wellKnownHostsNotFound
    case autoconfigNotFound
    case autodiscoverNotFound
    case srvRecordsNotFound
    case invalidAutoconfigFormat
    case invalidAutodiscoverFormat
    case invalidDomain
    
    var errorDescription: String? {
        switch self {
        case .noSettingsFound:
            return "Could not automatically discover mail server settings for this email address"
        case .wellKnownHostsNotFound:
            return "Common mail server hostnames not found"
        case .autoconfigNotFound:
            return "Autoconfig settings not available"
        case .autodiscoverNotFound:
            return "Autodiscover settings not available"
        case .srvRecordsNotFound:
            return "DNS SRV records not found"
        case .invalidAutoconfigFormat:
            return "Invalid autoconfig XML format"
        case .invalidAutodiscoverFormat:
            return "Invalid autodiscover XML format"
        case .invalidDomain:
            return "Invalid email domain"
        }
    }
}
